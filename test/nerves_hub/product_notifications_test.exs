defmodule NervesHub.ProductNotificationsTest do
  use NervesHub.DataCase, async: true

  import Ecto.Query

  alias NervesHub.Accounts.Scope
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.Products.Notification
  alias Phoenix.Socket.Broadcast

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)

    %{user: user, org: org, product: product}
  end

  describe "list_cards/4" do
    test "rolls up one kind raised on many devices into a card", %{user: user, org: org, product: product} do
      other_product = Fixtures.product_fixture(user, org)

      for product <- [product, other_product], n <- 1..30 do
        NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(
          product.id,
          "abc-#{n}",
          :shared_secrets
        )
      end

      assert Repo.aggregate(Notification, :count) == 60

      {[card], meta, nil} = NervesHub.ProductNotifications.list_cards(product)

      assert meta.total_count == 1
      assert %{key: "duplicate_device_identifier", devices: 30, occurrences: 30} = card
      assert card.title == "30 devices tried to connect with identifiers already in use."

      assert [%Notification{metadata: %{"identifier" => "abc-30"}} | _] =
               NervesHub.ProductNotifications.card_notifications(product, :duplicate_device_identifier, 10)
    end

    test "pages through the cards that aren't rolled up", %{product: product} do
      for n <- 1..30 do
        NervesHub.ProductNotifications.create_connecting_code_failure_notification!(
          %DeviceInfo{product_id: product.id, device_identifier: "abc-#{n}"},
          "code-#{n}",
          "boom"
        )
      end

      {cards, meta, _before} = NervesHub.ProductNotifications.list_cards(product, 2, 25)

      assert meta.total_pages == 2
      assert meta.total_count == 30
      assert length(cards) == 5
      assert Enum.all?(cards, &(&1.devices == 1))

      {_cards, meta, _before} = NervesHub.ProductNotifications.list_cards(product, 9, 25)
      assert meta.current_page == 2
    end
  end

  test "all notifications for a product can be dismissed", %{user: user, org: org, product: product} do
    other_product = Fixtures.product_fixture(user, org)

    NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(product.id, "abc", :shared_secrets)

    NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(
      other_product.id,
      "abc",
      :shared_secrets
    )

    notifications = Repo.all(Notification)

    assert length(notifications) == 2

    Scope.for_user(user)
    |> Scope.put_product(product)
    |> NervesHub.ProductNotifications.delete_all()

    notifications = Repo.all(Notification)

    assert length(notifications) == 1
  end

  test "if a notification already exists for a given key, its last_occurrence is updated and occurrence_count is incremented",
       %{product: product} do
    NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(product.id, "abc", :shared_secrets)
    NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(product.id, "abc", :shared_secrets)
    NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(product.id, "abc", :shared_secrets)

    notifications = Repo.all(Notification)

    assert length(notifications) == 1

    notification = notifications |> hd()

    assert notification |> Map.get(:title) == "A device tried to connect with an identifier already in use."
    assert notification |> Map.get(:message) =~ "'abc'"
    assert notification |> Map.get(:occurrence_count) == 3
  end

  test "a notification raised without a kind gets one when it happens again", %{product: product} do
    notification =
      NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(
        product.id,
        "abc",
        :shared_secrets
      )

    # As a node on a release from before kinds would have raised it.
    Repo.update_all(from(n in Notification, where: n.id == ^notification.id), set: [kind: nil])

    NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(product.id, "abc", :shared_secrets)

    assert %Notification{kind: :duplicate_device_identifier, occurrence_count: 2} =
             Repo.get!(Notification, notification.id)
  end

  test "a broadcast is sent to the product's channel when a notification is created",
       %{product: product} do
    NervesHub.ProductNotifications.subscribe(product.id)
    NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(product.id, "abc", :shared_secrets)
    assert_receive %Broadcast{event: "created"}
  end

  test "creates a notification when a device connects with no firmware metadata",
       %{product: product} do
    device = %Device{product_id: product.id, identifier: "no-firmware-metadata"}

    notification = NervesHub.ProductNotifications.create_missing_firmware_metadata_notification!(device)

    assert notification.product_id == product.id
    assert notification.level == :warning
    assert notification.kind == :missing_firmware_metadata
    assert notification.title == "A device connected without firmware metadata."
    assert notification.message =~ "'no-firmware-metadata'"
    assert notification.metadata == %{identifier: device.identifier}
    assert notification.event_key == "missing_firmware_metadata-#{device.identifier}"
    assert notification.occurrence_count == 1
  end

  describe "create_connecting_code_failure_notification!/3" do
    test "names the device and the reason", %{product: product} do
      device_info = %DeviceInfo{product_id: product.id, device_identifier: "connecting-code-1"}

      notification =
        NervesHub.ProductNotifications.create_connecting_code_failure_notification!(
          device_info,
          ~s/raise "boom"/,
          "** (RuntimeError) boom"
        )

      assert notification.level == :warning
      assert notification.title == "A device could not run its connecting code."
      assert notification.message =~ "'connecting-code-1'"
      assert notification.message =~ ": ** (RuntimeError) boom."
      assert notification.metadata == %{identifier: "connecting-code-1", reason: "** (RuntimeError) boom"}
    end

    # A deployment group's code that is wrong fails on every device in the group.
    test "devices failing on the same code share one notification", %{product: product} do
      for identifier <- ["connecting-code-1", "connecting-code-2"] do
        NervesHub.ProductNotifications.create_connecting_code_failure_notification!(
          %DeviceInfo{product_id: product.id, device_identifier: identifier},
          ~s/raise "boom"/,
          "** (RuntimeError) boom"
        )
      end

      assert [notification] = Repo.all(Notification)
      assert notification.occurrence_count == 2
      assert notification.message =~ "'connecting-code-1'"
    end

    test "different code is a different notification", %{product: product} do
      device_info = %DeviceInfo{product_id: product.id, device_identifier: "connecting-code-1"}

      for code <- [~s/raise "boom"/, ~s/raise "bang"/] do
        NervesHub.ProductNotifications.create_connecting_code_failure_notification!(device_info, code, nil)
      end

      assert Repo.aggregate(Notification, :count) == 2
    end

    test "caps a long reason", %{product: product} do
      device_info = %DeviceInfo{product_id: product.id, device_identifier: "connecting-code-1"}

      notification =
        NervesHub.ProductNotifications.create_connecting_code_failure_notification!(
          device_info,
          "IO.puts(:loud)",
          String.duplicate("a", 1_000)
        )

      assert String.length(notification.metadata.reason) == 200
    end
  end

  defp scope(user, product), do: user |> Scope.for_user() |> Scope.put_product(product)

  describe "levels" do
    test "counts each level and lists one at a time", %{product: product} do
      _ =
        NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(
          product.id,
          "a",
          :shared_secrets
        )

      _ =
        NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(
          product.id,
          "b",
          :shared_secrets
        )

      _ = NervesHub.ProductNotifications.create_device_async_bulk_create_notification!(product.id, 0, 3, "csv")

      # The two devices' notifications are one card.
      assert NervesHub.ProductNotifications.level_counts(product) == %{all: 2, error: 1, warning: 1, info: 0}

      {[warning], meta, _before} = NervesHub.ProductNotifications.list_cards(product, 1, 25, :warning)
      assert meta.total_count == 1
      assert %{level: :warning, devices: 2} = warning
    end

    test "a page that continues another knows when the one before it happened", %{product: product} do
      now = DateTime.truncate(DateTime.utc_now(), :second)

      for n <- 1..3 do
        notification =
          NervesHub.ProductNotifications.create_connecting_code_failure_notification!(
            %DeviceInfo{product_id: product.id, device_identifier: "abc-#{n}"},
            "code-#{n}",
            "boom"
          )

        Repo.update_all(from(x in Notification, where: x.id == ^notification.id),
          set: [last_occurred_at: DateTime.add(now, -n, :minute)]
        )
      end

      assert {_cards, _meta, nil} = NervesHub.ProductNotifications.list_cards(product, 1, 2)
      assert {[_third], _meta, before} = NervesHub.ProductNotifications.list_cards(product, 2, 2)
      assert before == DateTime.add(now, -2, :minute)
    end
  end

  describe "dismiss/2" do
    test "dismisses one of the product's notifications and tells its page", %{user: user, product: product} do
      :ok = NervesHub.ProductNotifications.subscribe(product.id)

      notification =
        NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(
          product.id,
          "abc",
          :shared_secrets
        )

      assert_receive %Broadcast{event: "created"}

      assert {:ok, %Notification{id: id}} =
               NervesHub.ProductNotifications.dismiss(scope(user, product), notification.id)

      assert id == notification.id
      assert_receive %Broadcast{event: "resolved"}
      assert Repo.all(Notification) == []
    end

    test "leaves another product's alone", %{user: user, org: org, product: product} do
      other_product = Fixtures.product_fixture(user, org)

      notification =
        NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(
          other_product.id,
          "abc",
          :shared_secrets
        )

      assert {:error, :not_found} = NervesHub.ProductNotifications.dismiss(scope(user, product), notification.id)
      assert {:error, :not_found} = NervesHub.ProductNotifications.dismiss(scope(user, product), "not-a-uuid")
      assert Repo.aggregate(Notification, :count) == 1
    end

    test "dismissing all of them says who did it and how many cards went", %{user: user, product: product} do
      :ok = NervesHub.ProductNotifications.subscribe(product.id)

      for identifier <- ["a", "b"] do
        NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(
          product.id,
          identifier,
          :shared_secrets
        )
      end

      _ = NervesHub.ProductNotifications.create_device_async_bulk_create_notification!(product.id, 0, 3, "csv")

      :ok = NervesHub.ProductNotifications.delete_all(scope(user, product))

      # The two devices' notifications were one card.
      assert_receive %Broadcast{event: "dismissed", payload: %{dismissed_by: %{id: user_id}, count: 2}}
      assert Repo.all(Notification) == []
      assert user_id == user.id
    end
  end

  describe "dismiss_card/2" do
    test "dismisses every device's notification of a kind, only in the product", %{
      user: user,
      org: org,
      product: product
    } do
      other_product = Fixtures.product_fixture(user, org)
      :ok = NervesHub.ProductNotifications.subscribe(product.id)

      for product <- [product, other_product], identifier <- ["a", "b"] do
        NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(
          product.id,
          identifier,
          :shared_secrets
        )
      end

      _ = NervesHub.ProductNotifications.create_device_async_bulk_create_notification!(product.id, 0, 3, "csv")

      assert {:ok, 2} = NervesHub.ProductNotifications.dismiss_card(scope(user, product), "duplicate_device_identifier")
      assert_receive %Broadcast{event: "resolved"}

      assert Repo.aggregate(where(Notification, product_id: ^product.id), :count) == 1
      assert Repo.aggregate(where(Notification, product_id: ^other_product.id), :count) == 2
    end

    test "only dismisses a kind that's rolled up", %{user: user, product: product} do
      _ = NervesHub.ProductNotifications.create_device_async_bulk_create_notification!(product.id, 0, 3, "csv")

      assert {:error, :not_found} =
               NervesHub.ProductNotifications.dismiss_card(scope(user, product), "device_bulk_create")

      assert {:error, :not_found} = NervesHub.ProductNotifications.dismiss_card(scope(user, product), "nonsense")

      assert {:error, :not_found} =
               NervesHub.ProductNotifications.dismiss_card(scope(user, product), "wrong_websocket_host")

      assert Repo.aggregate(Notification, :count) == 1
    end
  end

  describe "subjects/2" do
    @describetag :tmp_dir

    setup %{user: user, org: org, product: product, tmp_dir: tmp_dir} do
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      %{firmware: firmware}
    end

    defp subjects(user, product, notifications) do
      NervesHub.ProductNotifications.subjects(scope(user, product), notifications)
    end

    test "a device in the product, deleted from it, or moved out of it", %{
      user: user,
      org: org,
      product: product,
      firmware: firmware
    } do
      here = Fixtures.device_fixture(org, product, firmware)
      deleted = Fixtures.device_fixture(org, product, firmware)
      {:ok, _} = Devices.delete_device(deleted)
      moved = Fixtures.device_fixture(org, Fixtures.product_fixture(user, org), firmware)

      notifications =
        for device <- [
              here,
              deleted,
              %{moved | product_id: product.id},
              %Device{product_id: product.id, identifier: "gone"}
            ] do
          NervesHub.ProductNotifications.create_missing_firmware_metadata_notification!(device)
        end

      subjects = subjects(user, product, Repo.all(Notification))

      assert [
               %{kind: :device, label: here_label, state: :live, ref: here_ref},
               %{state: :deleted, ref: nil},
               %{state: :moved, ref: nil},
               %{state: :deleted, label: "gone"}
             ] = Enum.map(notifications, &subjects[&1.id])

      assert here_label == here.identifier
      assert here_ref == here.identifier
    end

    test "a deployment group, found by its ID after it was renamed", %{user: user, product: product, firmware: firmware} do
      group = Fixtures.deployment_group_fixture(firmware, %{user: user})
      step = %DeploymentWorkflowStep{id: 1, number: 2, type: :approval_required}

      notification =
        NervesHub.ProductNotifications.create_workflow_halted_notification!(group, step, :awaiting_approval)

      {:ok, _} = NervesHub.ManagedDeployments.update_deployment_group(group, %{name: "Renamed"}, user)

      assert %{kind: :deployment_group, label: label, state: :live, ref: "Renamed"} =
               subjects(user, product, Repo.all(Notification))[notification.id]

      assert label == group.name
    end

    test "an integration that was turned off, and one since removed", %{user: user, org: org, product: product} do
      {:ok, webhook} =
        NervesHub.Webhooks.create_webhook(%Scope{org: org, user: user}, %{
          "url" => "https://hooks.example.com/nerves",
          "events" => ["device.connected"]
        })

      [kept] = NervesHub.ProductNotifications.create_webhook_disabled_notifications!(webhook, [product.id], "it failed")

      [removed] =
        NervesHub.ProductNotifications.create_webhook_disabled_notifications!(
          %{webhook | id: webhook.id + 1_000},
          [product.id],
          "it failed"
        )

      subjects = subjects(user, product, Repo.all(Notification))

      assert %{kind: :webhook, label: "hooks.example.com", state: :live} = subjects[kept.id]
      assert %{kind: :webhook, state: :removed} = subjects[removed.id]
    end

    test "nothing for a notification about nothing in particular", %{user: user, product: product} do
      notification =
        NervesHub.ProductNotifications.create_device_async_bulk_create_notification!(product.id, 3, 0, "csv")

      refute Map.has_key?(subjects(user, product, Repo.all(Notification)), notification.id)
    end
  end
end
