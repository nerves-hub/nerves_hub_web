defmodule NervesHub.DeviceLinkTest do
  use NervesHub.DataCase, async: true
  use Mimic

  alias NervesHub.DeviceLink
  alias NervesHub.Devices
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{is_active: true, user: user})
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
      :ok = DeviceLink.status_update(device, %{"status" => "Update failed: encountered fwup error"}, true)

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
      :ok = DeviceLink.status_update(device, %{"status" => "FWUP error: failure of some sort"}, true)

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
      :ok = DeviceLink.status_update(device, %{"status" => "Update in progress: downloading firmware"}, true)

      # Verify the inflight update still exists
      assert [%InflightUpdate{}] =
               InflightUpdate
               |> Repo.all()
               |> Repo.preload([:device])
               |> Enum.filter(&(&1.device_id == device.id))
    end

    test "'started' messages from device execute telemetry when there's a network interface mismatch", %{device: device} do
      {:ok, device} = Devices.update_network_interface(device, "wlan0")

      expect(:telemetry, :execute, fn _event, _measurements, metadata ->
        assert metadata.downloader_network_interface == "eth0"
        assert metadata.device_network_interface == :wifi
      end)

      :ok = DeviceLink.status_update(device, %{"status" => "started", "downloader_network_interface" => "eth0"}, false)
    end
  end
end
