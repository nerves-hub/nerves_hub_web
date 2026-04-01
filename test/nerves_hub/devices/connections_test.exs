defmodule NervesHub.Devices.ConnectionsTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Fixtures
  alias Phoenix.Socket.Broadcast

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    {:ok, %{device: device, product: product}}
  end

  describe "connection lifecycle" do
    test "returns nil when device never connected", %{device: device} do
      refute Connections.get_latest_for_device(device.id)
    end

    test "transitions through connecting -> connected -> disconnected states", %{device: device} do
      topic = "device:#{device.identifier}:internal"
      Phoenix.PubSub.subscribe(NervesHub.PubSub, topic)

      assert {:ok, %DeviceConnection{id: ref, status: :connecting}} =
               Connections.device_connecting(device, device.product_id)

      assert %DeviceConnection{status: :connecting} = Connections.get_latest_for_device(device.id)
      assert_receive %Broadcast{topic: ^topic, event: "connection:change", payload: %{status: "connecting"}}, 500

      assert :ok = Connections.device_connected(device, ref)
      assert %DeviceConnection{status: :connected} = Connections.get_latest_for_device(device.id)
      assert_receive %Broadcast{topic: ^topic, event: "connection:change", payload: %{status: "online"}}, 500

      assert :ok = Connections.device_disconnected(device, ref)

      assert %DeviceConnection{status: :disconnected, disconnected_at: disconnected_at} =
               Connections.get_latest_for_device(device.id)

      refute is_nil(disconnected_at)
      assert_receive %Broadcast{topic: ^topic, event: "connection:change", payload: %{status: "offline"}}, 500
    end
  end

  describe "device_heartbeat/2" do
    test "updates last_seen_at and broadcasts heartbeat event", %{device: device} do
      topic = "device:#{device.identifier}:internal"
      Phoenix.PubSub.subscribe(NervesHub.PubSub, topic)

      assert {:ok, %DeviceConnection{id: connection_id, last_seen_at: first_seen_at} = connection} =
               Connections.device_connecting(device, device.product_id)

      assert_receive %Broadcast{topic: ^topic, event: "connection:change", payload: %{status: "connecting"}}, 500

      assert :ok = Connections.device_connected(device, connection_id)

      assert_receive %Broadcast{topic: ^topic, event: "connection:change", payload: %{status: "online"}}, 500

      Connections.device_heartbeat(device, connection_id)

      assert_receive %Broadcast{topic: ^topic, event: "connection:heartbeat"}, 500

      %DeviceConnection{id: ^connection_id, last_seen_at: last_seen_at, status: :connected} =
        Repo.reload(connection)

      assert last_seen_at > first_seen_at
      assert %DeviceConnection{status: :connected} = Connections.get_latest_for_device(device.id)
    end
  end

  describe "delete_old_connections/0" do
    test "deletes connections older than configured retention period", %{device: device} do
      {:ok, _} = Connections.device_connecting(device, device.product_id)
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

    test "never deletes a device's latest connection", %{device: device} do
      {:ok, _} = Connections.device_connecting(device, device.product_id)

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

  describe "clean_stale_connections/0" do
    test "marks stale connected connections as disconnected", %{device: device} do
      {:ok, connection} = Connections.device_connecting(device, device.product_id)
      :ok = Connections.device_connected(device, connection.id)

      # Get the configured interval and jitter
      interval = Application.get_env(:nerves_hub, :device_last_seen_update_interval_minutes)
      jitter = Application.get_env(:nerves_hub, :device_last_seen_update_interval_jitter_seconds)
      max_jitter = ceil(jitter / 60)

      # Set last_seen_at to be older than interval + jitter to make it stale
      stale_time = DateTime.utc_now() |> DateTime.add(-(interval + max_jitter + 2), :minute)

      connection
      |> Ecto.Changeset.change(%{last_seen_at: stale_time})
      |> Repo.update!()

      assert :ok = Connections.clean_stale_connections()

      updated_connection = Repo.reload(connection)
      assert updated_connection.status == :disconnected
      assert updated_connection.disconnected_reason == "Stale connection"
      refute is_nil(updated_connection.disconnected_at)
    end

    test "does not mark recent connections as stale", %{device: device} do
      {:ok, connection} = Connections.device_connecting(device, device.product_id)
      :ok = Connections.device_connected(device, connection.id)

      # Set last_seen_at to recent time
      recent_time = DateTime.utc_now() |> DateTime.add(-5, :minute)

      connection
      |> Ecto.Changeset.change(%{last_seen_at: recent_time})
      |> Repo.update!()

      assert :ok = Connections.clean_stale_connections()

      updated_connection = Repo.reload(connection)
      assert updated_connection.status == :connected
      assert is_nil(updated_connection.disconnected_at)
    end

    test "only marks connected connections as stale, not already disconnected ones", %{
      device: device
    } do
      # Get the configured interval and jitter
      interval = Application.get_env(:nerves_hub, :device_last_seen_update_interval_minutes)
      jitter = Application.get_env(:nerves_hub, :device_last_seen_update_interval_jitter_seconds)
      max_jitter = ceil(jitter / 60)
      stale_time = DateTime.utc_now() |> DateTime.add(-(interval + max_jitter + 2), :minute)

      # Create a connection and then disconnect it manually
      disconnected_connection =
        Fixtures.device_connection_fixture(device, %{
          status: :connected,
          last_seen_at: stale_time
        })

      # Now update it to disconnected with a reason
      disconnected_connection =
        disconnected_connection
        |> Ecto.Changeset.change(%{
          status: :disconnected,
          disconnected_at: DateTime.utc_now(),
          disconnected_reason: "Manual disconnect"
        })
        |> Repo.update!()

      assert :ok = Connections.clean_stale_connections()

      updated_connection = Repo.reload(disconnected_connection)
      assert updated_connection.status == :disconnected
      assert updated_connection.disconnected_reason == "Manual disconnect"
    end

    test "processes connections in batches respecting the update limit", %{
      device: device
    } do
      # Get the configured interval and jitter
      interval = Application.get_env(:nerves_hub, :device_last_seen_update_interval_minutes)
      jitter = Application.get_env(:nerves_hub, :device_last_seen_update_interval_jitter_seconds)
      max_jitter = ceil(jitter / 60)
      stale_time = DateTime.utc_now() |> DateTime.add(-(interval + max_jitter + 2), :minute)

      # Create multiple stale connections for the same device
      connections =
        for _ <- 1..5 do
          Fixtures.device_connection_fixture(device, %{
            status: :connected,
            last_seen_at: stale_time
          })
        end

      # Set a small batch limit to test batching
      original_limit = Application.get_env(:nerves_hub, :device_connection_update_limit)

      try do
        Application.put_env(:nerves_hub, :device_connection_update_limit, 2)

        assert :ok = Connections.clean_stale_connections()

        # All connections should be marked as disconnected
        for connection <- connections do
          updated = Repo.reload(connection)
          assert updated.status == :disconnected
          assert updated.disconnected_reason == "Stale connection"
        end
      after
        Application.put_env(:nerves_hub, :device_connection_update_limit, original_limit)
      end
    end
  end
end
