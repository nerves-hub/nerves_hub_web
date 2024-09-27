defmodule NervesHub.Devices.Connections do
  @moduledoc """
  Handles connection data for devices, reported from device socket.
  """
  import Ecto.Query

  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Repo

  def get_device_connections(device_id) do
    DeviceConnection
    |> where(device_id: ^device_id)
    |> order_by(asc: :last_seen_at)
    |> Repo.all()
  end

  def latest_connection_preload_query() do
    DeviceConnection
    |> distinct(:device_id)
    |> order_by([:device_id, desc: :last_seen_at])
  end

  def device_connected(device_id) do
    now = DateTime.utc_now()

    %{
      device_id: device_id,
      established_at: now,
      last_seen_at: now,
      status: :connected
    }
    |> DeviceConnection.connected_changeset()
    |> NervesHub.Repo.insert()
  end

  def device_disconnected(device_id, reason \\ nil) do
    now = DateTime.utc_now()

    %{
      device_id: device_id,
      disconnected_at: now,
      disconnected_reason: reason,
      last_seen_at: now,
      status: :disconnected
    }
    |> DeviceConnection.disconnected_changeset()
    |> NervesHub.Repo.insert()
  end

  def device_heartbeat(device_id, established_at) do
    %{
      device_id: device_id,
      last_seen_at: DateTime.utc_now(),
      established_at: established_at,
      status: :connected
    }
    |> DeviceConnection.heartbeat_changeset()
    |> NervesHub.Repo.insert()
  end
end
