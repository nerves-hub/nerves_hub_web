defmodule NervesHub.DeviceConnectionsTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Devices
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
    assert Connections.get_current_status(device.id) == :not_seen
  end

  test "device connect", %{device: device} do
    assert {:ok, %DeviceConnection{status: :connected}} = Connections.device_connected(device.id)
    assert Connections.get_current_status(device.id) == :connected
  end

  test "device heartbeat", %{device: device} do
    assert {:ok, %DeviceConnection{id: connection_id, last_seen_at: first_seen_at}} =
             Connections.device_connected(device.id)

    assert {:ok,
            %DeviceConnection{id: ^connection_id, last_seen_at: last_seen_at, status: :connected}} =
             Connections.device_heartbeat(connection_id)

    assert last_seen_at > first_seen_at
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

    assert Connections.get_current_status(device.id) == :disconnected
  end

  test "get device with latest connection preloaded", %{device: device} do
    assert {:ok, %DeviceConnection{}} = Connections.device_connected(device.id)

    %{device_connections: [connection]} =
      Devices.get_device(device.id, :preload_latest_connection)

    assert connection.status == :connected
  end
end
