defmodule NervesHub.DeviceEventsTest do
  @moduledoc """
  Tests for the update messages sent to a single device.

  Deployments and manual pushes build the update payload separately, and it is
  easy for the two to drift. What the device needs to verify and resume a
  download - the size and checksums of the file it is about to fetch - has to be
  in both.
  """

  use NervesHub.DataCase, async: true

  alias NervesHub.Accounts
  alias NervesHub.DeviceEvents
  alias NervesHub.FirmwareUpdates
  alias NervesHub.Fixtures
  alias NervesHub.Products
  alias Phoenix.Socket.Broadcast

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, DeviceEvents.topic(device))

    {:ok,
     %{
       device: device,
       firmware: firmware,
       org: org,
       org_key: org_key,
       product: product,
       tmp_dir: tmp_dir,
       user: user
     }}
  end

  describe "manual_update/4" do
    test "describes the firmware being sent", context do
      %{device: device, org_key: org_key, product: product, tmp_dir: tmp_dir, user: user} = context

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      {:ok, _device} = DeviceEvents.manual_update(device, new_firmware, user)

      assert_receive %Broadcast{event: "update", payload: payload}

      assert payload.update_available
      assert payload.firmware_meta.uuid == new_firmware.uuid

      # without these the device can't check what it downloaded, or pick up
      # where it left off after a restart
      assert payload.size == new_firmware.size
      assert payload.checksum == new_firmware.checksum
      assert payload.partials_checksums == new_firmware.partials_checksums

      refute is_nil(payload.checksum)
      refute payload.partials_checksums == []
    end

    test "describes the delta being sent rather than the firmware it produces", context do
      %{device: device, firmware: firmware, org_key: org_key} = context
      %{product: product, tmp_dir: tmp_dir, user: user} = context

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      # a delta has its own size and checksums, because the delta is the file
      # the device downloads
      delta =
        firmware
        |> Fixtures.firmware_delta_fixture(new_firmware)
        |> Ecto.Changeset.change(%{
          checksum: String.duplicate("A", 64),
          partials_checksums: [String.duplicate("B", 64), String.duplicate("C", 64)]
        })
        |> Repo.update!()

      {:ok, _device} = DeviceEvents.manual_update(device, new_firmware, user, delta: true)

      assert_receive %Broadcast{event: "update", payload: payload}

      # the metadata still describes the firmware the device ends up running
      assert payload.firmware_meta.uuid == new_firmware.uuid

      assert payload.size == delta.size
      assert payload.checksum == delta.checksum
      assert payload.partials_checksums == delta.partials_checksums

      refute payload.size == new_firmware.size
      refute payload.checksum == new_firmware.checksum
    end

    # Sending firmware twice, or to a device a deployment group is already
    # updating, used to crash on the inflight row's unique index.
    test "is refused while the device is already updating", context do
      %{device: device, org_key: org_key, product: product, tmp_dir: tmp_dir, user: user} = context

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      {:ok, device} = DeviceEvents.manual_update(device, new_firmware, user)
      assert_receive %Broadcast{event: "update"}

      assert {:error, :already_updating} = DeviceEvents.manual_update(device, new_firmware, user)
      refute_receive %Broadcast{event: "update"}, 200

      # the first request is the one still recorded
      assert %{firmware_uuid: firmware_uuid} = FirmwareUpdates.inflight_update_for(device)
      assert firmware_uuid == new_firmware.uuid
    end
  end

  # The devices stay when their product or org is deleted, and are refused when
  # they reconnect, so what has to happen here is that they reconnect.
  describe "closing the connections of a deleted product's devices" do
    setup context do
      other_product = Fixtures.product_fixture(context.user, context.org, %{name: "other_product"})
      other_org = Fixtures.org_fixture(context.user, %{name: "other_org"})
      other_org_product = Fixtures.product_fixture(context.user, other_org)

      Fixtures.device_connection_fixture(context.device)

      devices = %{
        same_product_offline: Fixtures.device_fixture(context.org, context.product, context.firmware),
        other_product: connected(context.org, other_product, context.firmware),
        other_org: connected(other_org, other_org_product, context.firmware)
      }

      for {_name, device} <- devices, do: subscribe(device)
      subscribe(context.device)

      %{others: devices, other_product: other_product}
    end

    test "deleting the org closes the connections of every product's devices, and no other org's", context do
      {:ok, _} = Accounts.soft_delete_org(context.org)

      assert_disconnected(context.device)
      assert_disconnected(context.others.other_product)
      refute_disconnected(context.others.other_org)
      refute_disconnected(context.others.same_product_offline)
    end

    test "closing an account closes the connections of the devices in the orgs it was the last member of",
         context do
      # Someone else still belongs to the other org, so it outlives the account.
      other_org = Accounts.get_org!(context.others.other_org.org_id)
      {:ok, _} = Accounts.add_org_user(other_org, Fixtures.user_fixture(), %{role: :admin})

      {:ok, _} = Accounts.remove_account(context.user.id)

      assert_disconnected(context.device)
      assert_disconnected(context.others.other_product)
      refute_disconnected(context.others.other_org)
      refute_disconnected(context.others.same_product_offline)
    end

    test "deleting a product closes the connections of its devices only", context do
      {:ok, _} = Products.delete_product(context.product)

      assert_disconnected(context.device)
      refute_disconnected(context.others.other_product)
      refute_disconnected(context.others.other_org)
    end

    defp connected(org, product, firmware) do
      device = Fixtures.device_fixture(org, product, firmware)
      Fixtures.device_connection_fixture(device)
      device
    end

    defp subscribe(device), do: :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, "device_socket:#{device.id}")

    defp assert_disconnected(device) do
      topic = "device_socket:#{device.id}"
      assert_receive %Broadcast{topic: ^topic, event: "disconnect"}
    end

    defp refute_disconnected(device) do
      topic = "device_socket:#{device.id}"
      refute_received %Broadcast{topic: ^topic, event: "disconnect"}
    end
  end
end
