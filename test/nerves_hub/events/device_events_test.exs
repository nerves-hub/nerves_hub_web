defmodule NervesHub.DeviceEventsTest do
  @moduledoc """
  Tests for the update messages sent to a single device.

  Deployments and manual pushes build the update payload separately, and it is
  easy for the two to drift. What the device needs to verify and resume a
  download - the size and checksums of the file it is about to fetch - has to be
  in both.
  """

  use NervesHub.DataCase, async: true

  import Ecto.Query, only: [where: 2]

  alias NervesHub.DeviceEvents
  alias NervesHub.Devices.Device
  alias NervesHub.Fixtures
  alias NervesHub.Repo
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

  describe "deployment_changed_for_many/2" do
    setup %{org: org, product: product, firmware: firmware, user: user} do
      first_group = Fixtures.deployment_group_fixture(firmware, %{name: "First group", user: user})
      second_group = Fixtures.deployment_group_fixture(firmware, %{name: "Second group", user: user})

      # A whole batch, so a device after them is in the second batch, which
      # waits out the pause before it's sent
      now = NaiveDateTime.utc_now(:second)

      rows =
        for n <- 1..2_500 do
          %{
            org_id: org.id,
            product_id: product.id,
            deployment_id: first_group.id,
            identifier: "first-batch-#{System.unique_integer([:positive])}-#{n}",
            inserted_at: now,
            updated_at: now
          }
        end

      {2_500, inserted} = Repo.insert_all(Device, rows, returning: [:id])

      %{first_group: first_group, second_group: second_group, first_batch_ids: Enum.map(inserted, & &1.id)}
    end

    test "leaves out a device moved again before its batch is sent", context do
      %{device: device, first_group: first_group, second_group: second_group} = context
      first_id = first_group.id
      topic = DeviceEvents.topic(device)

      {1, _} = Repo.update_all(where(Device, id: ^device.id), set: [deployment_id: first_id])

      :ok = DeviceEvents.deployment_changed_for_many(context.first_batch_ids ++ [device.id], first_id)

      # Moved on while the first batch is out and the pause has begun
      {1, _} = Repo.update_all(where(Device, id: ^device.id), set: [deployment_id: second_group.id])

      # Well past the pause, so the second batch has gone out
      refute_receive %Broadcast{topic: ^topic, event: "deployment_updated", payload: %{deployment_id: ^first_id}}, 500
    end

    test "still tells a device that hasn't moved since", context do
      %{device: device, first_group: first_group} = context
      first_id = first_group.id
      topic = DeviceEvents.topic(device)

      {1, _} = Repo.update_all(where(Device, id: ^device.id), set: [deployment_id: first_id])

      :ok = DeviceEvents.deployment_changed_for_many(context.first_batch_ids ++ [device.id], first_id)

      assert_receive %Broadcast{topic: ^topic, event: "deployment_updated", payload: %{deployment_id: ^first_id}}, 1_000
    end

    test "tells a device removed from its group, and only while it's still out", context do
      %{device: device, first_group: first_group} = context
      topic = DeviceEvents.topic(device)

      :ok = DeviceEvents.deployment_changed_for_many(context.first_batch_ids ++ [device.id], nil)

      assert_receive %Broadcast{topic: ^topic, event: "deployment_updated", payload: %{deployment_id: nil}}, 1_000

      other = Fixtures.device_fixture(context.org, context.product, context.firmware)
      other_topic = DeviceEvents.topic(other)
      :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, other_topic)

      :ok = DeviceEvents.deployment_changed_for_many(context.first_batch_ids ++ [other.id], nil)
      {1, _} = Repo.update_all(where(Device, id: ^other.id), set: [deployment_id: first_group.id])

      refute_receive %Broadcast{topic: ^other_topic, event: "deployment_updated"}, 500
    end
  end
end
