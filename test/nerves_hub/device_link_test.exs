defmodule NervesHub.DeviceLinkTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.DeviceLink
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
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
end
