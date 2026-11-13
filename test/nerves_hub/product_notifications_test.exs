defmodule NervesHub.ProductNotificationsTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Accounts.Scope
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Device
  alias NervesHub.Fixtures
  alias NervesHub.Products.Notification
  alias Phoenix.Socket.Broadcast

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)

    %{user: user, org: org, product: product}
  end

  test "can paginate through notifications", %{user: user, org: org, product: product} do
    other_product = Fixtures.product_fixture(user, org)

    for n <- 1..30 do
      NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(
        product.id,
        "abc-#{n}",
        :shared_secrets
      )
    end

    for n <- 1..30 do
      NervesHub.ProductNotifications.create_duplicate_device_identifier_notification!(
        other_product.id,
        "abc-#{n}",
        :shared_secrets
      )
    end

    notifications = Repo.all(Notification)

    assert length(notifications) == 60

    {_list, meta} = NervesHub.ProductNotifications.paginated_list(product)

    assert meta.total_pages == 2
    assert meta.total_count == 30
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

    assert notification |> Map.get(:title) == "A device failed connecting as the identifier 'abc' already exists."
    assert notification |> Map.get(:occurrence_count) == 3
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
    assert notification.title == "A device connected without any firmware metadata."
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
end
