defmodule NervesHub.TrackerTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Fixtures
  alias NervesHub.Tracker

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    device = Fixtures.device_fixture(org, product, firmware)

    %{device: device}
  end

  describe "heartbeat/1" do
    test "accepts a Device struct", %{device: device} do
      assert :ok = Tracker.heartbeat(device)
    end

    test "accepts a device_id integer", %{device: device} do
      assert :ok = Tracker.heartbeat(device.id)
    end
  end

  describe "connecting/1" do
    test "accepts a Device struct", %{device: device} do
      assert :ok = Tracker.connecting(device)
    end

    test "accepts a device_id integer", %{device: device} do
      assert :ok = Tracker.connecting(device.id)
    end
  end

  describe "online/1" do
    test "accepts a Device struct", %{device: device} do
      assert :ok = Tracker.online(device)
    end

    test "accepts a device_id integer", %{device: device} do
      assert :ok = Tracker.online(device.id)
    end
  end

  describe "offline/1" do
    test "accepts a Device struct", %{device: device} do
      assert :ok = Tracker.offline(device)
    end

    test "accepts a device_id integer", %{device: device} do
      assert :ok = Tracker.offline(device.id)
    end
  end

  describe "online?/1" do
    test "returns false for a device with no connection", %{device: device} do
      device = NervesHub.Repo.preload(device, :latest_connection)
      refute Tracker.online?(device)
    end

    test "returns true for a device with a connected status" do
      device = %{latest_connection: %{status: :connected}}
      assert Tracker.online?(device)
    end

    test "returns false for a device with a disconnected status" do
      device = %{latest_connection: %{status: :disconnected}}
      refute Tracker.online?(device)
    end

    test "returns false for a device with nil latest_connection" do
      device = %{latest_connection: nil}
      refute Tracker.online?(device)
    end

    test "preloads unloaded latest_connection association", %{device: device} do
      # Device without preloaded latest_connection triggers the preload clause
      refute Tracker.online?(device)
    end
  end

  describe "connection_status/1" do
    test "returns 'online' for a connected device" do
      device = %{latest_connection: %{status: :connected}}
      assert Tracker.connection_status(device) == "online"
    end

    test "returns 'offline' for a disconnected device" do
      device = %{latest_connection: %{status: :disconnected}}
      assert Tracker.connection_status(device) == "offline"
    end
  end

  describe "console_active?/1" do
    test "accepts a Device struct and returns a boolean", %{device: device} do
      result = Tracker.console_active?(device)
      assert is_boolean(result)
    end

    test "accepts a device_id and returns a boolean", %{device: device} do
      result = Tracker.console_active?(device.id)
      assert is_boolean(result)
    end
  end
end
