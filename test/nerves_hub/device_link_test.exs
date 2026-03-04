defmodule NervesHub.DeviceLinkTest do
  use NervesHub.DataCase, async: true
  use Mimic

  alias NervesHub.DeviceLink
  alias NervesHub.Devices
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Firmwares
  alias NervesHub.Fixtures
  alias NervesHub.Repo
  alias NervesHub.Workers.FirmwareDeltaBuilder

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{is_active: true})
    device = Fixtures.device_fixture(org, product, firmware)

    {:ok,
     %{
       user: user,
       org: org,
       product: product,
       org_key: org_key,
       firmware: firmware,
       deployment_group: deployment_group,
       device: device
     }}
  end

  describe "status_update/2" do
    test "clears inflight update when status contains 'encountered fwup error'", %{
      device: device,
      deployment_group: deployment_group
    } do
      # Create an inflight update
      {:ok, _inflight_update} = Fixtures.inflight_update(device, deployment_group)

      # Verify the inflight update exists
      assert [%InflightUpdate{}] =
               InflightUpdate
               |> Repo.all()
               |> Repo.preload([:device])
               |> Enum.filter(&(&1.device_id == device.id))

      # Call status_update with a status containing "encountered fwup error"
      :ok = DeviceLink.status_update(device, "Update failed: encountered fwup error", true)

      # Verify the inflight update was cleared
      assert [] =
               InflightUpdate
               |> Repo.all()
               |> Repo.preload([:device])
               |> Enum.filter(&(&1.device_id == device.id))
    end

    test "clears inflight update when status contains 'FWUP error: failure of some sort'", %{
      device: device,
      deployment_group: deployment_group
    } do
      # Create an inflight update
      {:ok, _inflight_update} = Fixtures.inflight_update(device, deployment_group)

      # Verify the inflight update exists
      assert [%InflightUpdate{}] =
               InflightUpdate
               |> Repo.all()
               |> Repo.preload([:device])
               |> Enum.filter(&(&1.device_id == device.id))

      # Call status_update with a status containing "FWUP error: failure of some sort"
      :ok = DeviceLink.status_update(device, "FWUP error: failure of some sort", true)

      # Verify the inflight update was cleared
      assert [] =
               InflightUpdate
               |> Repo.all()
               |> Repo.preload([:device])
               |> Enum.filter(&(&1.device_id == device.id))
    end

    test "does not clear inflight update when status does not contain fwup error", %{
      device: device,
      deployment_group: deployment_group
    } do
      # Create an inflight update
      {:ok, _inflight_update} = Fixtures.inflight_update(device, deployment_group)

      # Verify the inflight update exists
      assert [%InflightUpdate{}] =
               InflightUpdate
               |> Repo.all()
               |> Repo.preload([:device])
               |> Enum.filter(&(&1.device_id == device.id))

      # Call status_update with a status that does not contain "fwup error"
      :ok = DeviceLink.status_update(device, "Update in progress: downloading firmware", true)

      # Verify the inflight update still exists
      assert [%InflightUpdate{}] =
               InflightUpdate
               |> Repo.all()
               |> Repo.preload([:device])
               |> Enum.filter(&(&1.device_id == device.id))
    end
  end

  describe "join/3 - delta generation" do
    test "triggers delta generation when device connects and is automatically assigned to delta-enabled deployment group",
         %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      # Create source firmware (what device is currently running)
      source_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})

      # Create target firmware for deployment
      target_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})

      # Create delta-enabled deployment group that matches all devices
      _deployment_group =
        Fixtures.deployment_group_fixture(target_firmware, %{
          is_active: true,
          delta_updatable: true,
          conditions: %{version: "", tags: []}
        })

      # Create device with source firmware (no deployment group yet)
      device = Fixtures.device_fixture(org, product, source_firmware, %{deployment_id: nil})

      # Create device connection
      {:ok, connection} = Devices.Connections.device_connecting(device, product.id)

      # Device joins - should automatically be assigned to deployment group and trigger delta
      assert {:ok, updated_device} = DeviceLink.join(device, connection.id, %{})

      # Verify device was assigned to deployment group
      assert updated_device.deployment_id != nil

      # Verify FirmwareDeltaBuilder job was enqueued
      assert_enqueued(
        worker: FirmwareDeltaBuilder,
        args: %{
          "source_id" => source_firmware.id,
          "target_id" => target_firmware.id
        },
        queue: "firmware_delta_builder"
      )
    end

    test "does not trigger delta generation when deployment group is inactive", %{
      tmp_dir: tmp_dir
    } do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      source_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})
      target_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})

      # Inactive deployment group
      _deployment_group =
        Fixtures.deployment_group_fixture(target_firmware, %{
          is_active: false,
          delta_updatable: true,
          conditions: %{version: "", tags: []}
        })

      device = Fixtures.device_fixture(org, product, source_firmware, %{deployment_id: nil})

      # Create device connection
      {:ok, connection} = Devices.Connections.device_connecting(device, product.id)

      # Should not call attempt_firmware_delta
      Firmwares
      |> reject(:attempt_firmware_delta, 3)

      assert {:ok, _device} = DeviceLink.join(device, connection.id, %{})

      # Verify no FirmwareDeltaBuilder job was enqueued
      refute_enqueued(worker: FirmwareDeltaBuilder)
    end

    test "does not trigger delta generation when delta_updatable is false", %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      source_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})
      target_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})

      # Active but delta_updatable is false
      _deployment_group =
        Fixtures.deployment_group_fixture(target_firmware, %{
          is_active: true,
          delta_updatable: false,
          conditions: %{version: "", tags: []}
        })

      device = Fixtures.device_fixture(org, product, source_firmware, %{deployment_id: nil})

      # Create device connection
      {:ok, connection} = Devices.Connections.device_connecting(device, product.id)

      # Should not call attempt_firmware_delta
      Firmwares
      |> reject(:attempt_firmware_delta, 3)

      assert {:ok, _device} = DeviceLink.join(device, connection.id, %{})

      # Verify no FirmwareDeltaBuilder job was enqueued
      refute_enqueued(worker: FirmwareDeltaBuilder)
    end

    test "does not trigger delta generation when device doesn't match any deployment groups", %{
      tmp_dir: tmp_dir
    } do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      source_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})
      target_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})

      # Deployment group with conditions that won't match the device
      _deployment_group =
        Fixtures.deployment_group_fixture(target_firmware, %{
          is_active: true,
          delta_updatable: true,
          conditions: %{version: "", tags: ["production"]}
        })

      # Device without matching tags
      device = Fixtures.device_fixture(org, product, source_firmware, %{deployment_id: nil, tags: []})

      # Create device connection
      {:ok, connection} = Devices.Connections.device_connecting(device, product.id)

      # Should not call attempt_firmware_delta
      Firmwares
      |> reject(:attempt_firmware_delta, 3)

      assert {:ok, _device} = DeviceLink.join(device, connection.id, %{})

      # Verify no FirmwareDeltaBuilder job was enqueued
      refute_enqueued(worker: FirmwareDeltaBuilder)
    end
  end
end
