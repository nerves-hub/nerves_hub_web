defmodule NervesHub.Devices.Connections do
  @moduledoc """
  Handles connection data for devices, reported from device socket.
  """
  import Ecto.Query

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Repo

  @doc """
  Get all connections for a device.
  """
  @spec get_device_connections(non_neg_integer()) :: [DeviceConnection.t()]
  def get_device_connections(device_id) do
    DeviceConnection
    |> where(device_id: ^device_id)
    |> order_by(asc: :last_seen_at)
    |> Repo.all()
  end

  @doc """
  Get latest inserted connection for a device.
  """
  @spec get_latest_for_device(non_neg_integer()) :: DeviceConnection.t() | nil
  def get_latest_for_device(device_id) do
    DeviceConnection
    |> where(device_id: ^device_id)
    |> order_by(desc: :last_seen_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Creates a device connection, reported from device socket
  """
  @spec device_connected(non_neg_integer()) ::
          {:ok, DeviceConnection.t()} | {:error, Ecto.Changeset.t()}
  def device_connected(device_id) do
    now = DateTime.utc_now()

    changeset =
      DeviceConnection.create_changeset(%{
        device_id: device_id,
        established_at: now,
        last_seen_at: now,
        status: :connected
      })

    case Repo.insert(changeset) do
      {:ok, device_connection} ->
        Device
        |> where(id: ^device_id)
        |> Repo.update_all(set: [latest_connection_id: device_connection.id])

        {:ok, device_connection}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Updates the `last_seen_at`field for a device connection with current timestamp
  """
  @spec device_heartbeat(UUIDv7.t()) :: {:ok, DeviceConnection.t()} | {:error, Ecto.Changeset.t()}
  def device_heartbeat(ref_id) do
    DeviceConnection
    |> Repo.get!(ref_id)
    |> DeviceConnection.update_changeset(%{last_seen_at: DateTime.utc_now()})
    |> Repo.update()
  end

  @doc """
  Updates `status` and relevant timestamps for a device connection record,
  and stores the reason for disconnection if provided.
  """
  @spec device_disconnected(UUIDv7.t(), String.t() | nil) ::
          {:ok, DeviceConnection.t()} | {:error, Ecto.Changeset.t()}
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

  def clean_stale_connections() do
    interval = Application.get_env(:nerves_hub, :device_last_seen_update_interval_minutes)
    a_minute_ago = DateTime.shift(DateTime.utc_now(), minute: -(interval + 1))

    DeviceConnection
    |> where(status: :connected)
    |> where([d], d.last_seen_at < ^a_minute_ago)
    |> Repo.update_all(
      set: [
        status: :disconnected,
        disconnected_at: DateTime.utc_now(),
        disconnected_reason: "Stale connection"
      ]
    )
  end

  def delete_old_connections() do
    interval = Application.get_env(:nerves_hub, :device_connection_max_age_days)
    delete_limit = Application.get_env(:nerves_hub, :device_connection_delete_limit)
    days_ago = DateTime.shift(DateTime.utc_now(), day: -interval)

    ids =
      DeviceConnection
      |> join(:inner, [dc], d in Device, on: dc.device_id == d.id)
      |> where([dc, _d], dc.last_seen_at < ^days_ago)
      |> where([dc, _d], dc.status != :connected)
      |> where([dc, d], dc.id != d.latest_connection_id)
      |> select([dc], dc.id)
      |> limit(^delete_limit)
      |> Repo.all()

    {delete_count, _} =
      DeviceConnection
      |> where([d], d.id in ^ids)
      |> Repo.delete_all()

    if delete_count == 0 do
      :ok
    else
      # relax stress on Ecto pool and go again
      Process.sleep(2000)
      delete_old_connections()
    end
  end
end
