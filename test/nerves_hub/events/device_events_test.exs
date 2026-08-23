defmodule NervesHub.DeviceEventsTest do
  @moduledoc """
  Tests for the update messages sent to a single device.

  Deployments and manual pushes build the update payload separately, and it is
  easy for the two to drift. What the device needs to verify and resume a
  download - the size and checksums of the file it is about to fetch - has to be
  in both.
  """

  use NervesHub.DataCase, async: true

  alias NervesHub.DeviceEvents
  alias NervesHub.Fixtures
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
  end
end
