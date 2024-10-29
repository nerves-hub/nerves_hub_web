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

  def get_latest_for_device(device_id) do
    DeviceConnection
    |> where(device_id: ^device_id)
    |> order_by(desc: :last_seen_at)
    |> limit(1)
    |> Repo.one()
  end

  def get_current_status(device_id) do
    DeviceConnection
    |> where(device_id: ^device_id)
    |> order_by(desc: :last_seen_at)
    |> limit(1)
    |> Repo.one()
    |> case do
      %DeviceConnection{status: status} -> status
      nil -> :not_seen
    end
  end

  def get_established_at(device_id) do
    device_id
    |> get_latest_for_device()
    |> case do
      %DeviceConnection{established_at: established_at} -> established_at
      _ -> nil
    end
  end

  def preload_latest_connection(query) do
    query
    |> preload(device_connections: ^distinct_on_device())
  end

  def device_connected(device_id) do
    now = DateTime.utc_now()

    %{
      device_id: device_id,
      established_at: now,
      last_seen_at: now,
      status: :connected
    }
    |> DeviceConnection.create_changeset()
    |> Repo.insert()
  end

  def device_heartbeat(ref_id) do
    DeviceConnection
    |> Repo.get!(ref_id)
    |> DeviceConnection.update_changeset(%{last_seen_at: DateTime.utc_now()})
    |> Repo.update()
  end

  def device_disconnected(ref_id, reason \\ nil) do
    now = DateTime.utc_now()

    DeviceConnection
    |> Repo.get!(ref_id)
    |> DeviceConnection.update_changeset(%{
      last_seen_at: now,
      disconnected_at: now,
      disconnected_reason: reason,
      status: :disconnected
    })
    |> Repo.update()
  end

  defp distinct_on_device() do
    DeviceConnection
    |> distinct(:device_id)
    |> order_by([:device_id, desc: :last_seen_at])
  end
end
