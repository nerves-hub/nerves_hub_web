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
    assert {:ok, %DeviceConnection{}} = Connections.device_connected(device.id)
    assert Connections.get_current_status(device.id) == :connected
  end

  test "device disconnect", %{device: device} do
    assert {:ok, %DeviceConnection{}} =
             Connections.device_disconnected(device.id, DateTime.utc_now())

    assert Connections.get_current_status(device.id) == :disconnected
  end

  test "get current status", %{device: device} do
    assert {:ok, %DeviceConnection{last_seen_at: connected_at}} =
             Connections.device_connected(device.id)


    assert {:ok, %DeviceConnection{}} = Connections.device_disconnected(device.id, connected_at)

    assert :disconnected == Connections.get_current_status(device.id)
  end

  test "get device with latest connection preloaded", %{device: device} do
    assert {:ok, %DeviceConnection{}} = Connections.device_connected(device.id)

    %{device_connections: [connection]} =
      Devices.get_device(device.id, :preload_latest_connection)

    assert connection.status == :connected
  end
end
