defmodule NervesHub.Devices.ConnectionsTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Fixtures

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    device = Fixtures.device_fixture(org, product, firmware)

    {:ok, %{device: device, product: product}}
  end

  test "device never connected", %{device: device} do
    refute Connections.get_latest_for_device(device.id)
  end

  test "device connect", %{device: device} do
    assert {:ok, %DeviceConnection{status: :connected}} = Connections.device_connected(device.id)
    assert %DeviceConnection{status: :connected} = Connections.get_latest_for_device(device.id)
  end

  test "device heartbeat", %{device: device} do
    assert {:ok, %DeviceConnection{id: connection_id, last_seen_at: first_seen_at} = connection} =
             Connections.device_connected(device.id)

    Connections.device_heartbeat(connection_id)

    %DeviceConnection{id: ^connection_id, last_seen_at: last_seen_at, status: :connected} =
      Repo.reload(connection)

    assert last_seen_at > first_seen_at
    assert %DeviceConnection{status: :connected} = Connections.get_latest_for_device(device.id)
  end

  test "device disconnect", %{device: device} do
    assert {:ok, %DeviceConnection{id: connection_id, status: :connected}} =
             Connections.device_connected(device.id)

    assert {:ok,
            %DeviceConnection{
              id: ^connection_id,
              status: :disconnected,
              disconnected_at: disconnected_at
            }} =
             Connections.device_disconnected(connection_id)

    refute is_nil(disconnected_at)

    assert %DeviceConnection{status: :disconnected} = Connections.get_latest_for_device(device.id)
  end

  test "deleting old device_connections", %{device: device} do
    {:ok, _} = Connections.device_connected(device.id)
    two_weeks_ago = DateTime.utc_now() |> DateTime.add(-14, :day)

    deleted_device_connection =
      Fixtures.device_connection_fixture(device, %{
        status: :disconnected,
        last_seen_at: two_weeks_ago
      })

    _ = Connections.delete_old_connections()

    refute Repo.reload(deleted_device_connection)

    assert device
           |> Repo.reload()
           |> Repo.preload(:latest_connection)
           |> Map.get(:latest_connection)
  end

  test "deleting old device_connections never deletes a devices's last device_connection", %{
    device: device
  } do
    {:ok, _} = Connections.device_connected(device.id)

    %{latest_connection: latest_connection} =
      device |> Repo.reload() |> Repo.preload(:latest_connection)

    two_weeks_ago = DateTime.utc_now() |> DateTime.add(-14, :day)

    latest_connection
    |> Ecto.Changeset.change(%{last_seen_at: two_weeks_ago})
    |> Repo.update!()

    _ = Connections.delete_old_connections()

    assert Repo.reload(latest_connection)
    assert Repo.reload(device) |> Map.get(:latest_connection_id)
  end
end
