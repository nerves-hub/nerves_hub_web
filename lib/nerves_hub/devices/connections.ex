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
  Preload latest respective connection in a device query.
  """
  @spec preload_latest_connection(Ecto.Query.t()) :: Ecto.Query.t()
  def preload_latest_connection(query) do
    query
    |> preload(device_connections: ^distinct_on_device())
  end

  @doc """
  Creates a device connection, reported from device socket
  """
  @spec device_connected(non_neg_integer()) ::
          {:ok, DeviceConnection.t()} | {:error, Ecto.Changeset.t()}
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

  @doc """
  Selects devices id's which has provided status in it's latest connection record.
  """
  @spec query_devices_with_connection_status(String.t()) :: Ecto.Query.t()
  def query_devices_with_connection_status(status) do
    (lr in subquery(latest_row_query()))
    |> from()
    |> where([lr], lr.rn == 1)
    |> where(
      [lr],
      lr.status == ^String.to_existing_atom(status)
    )
    |> join(:inner, [lr], d in Device, on: lr.device_id == d.id)
    |> select([lr, d], d.id)
  end

  @doc """
  Generates a query to retrieve the most recent `DeviceConnection` for devices.
  The query includes the row number (`rn`)
  for each record, which is used to identify the most recent connection.

  Returns an Ecto query.
  """
  @spec latest_row_query() :: Ecto.Query.t()
  def latest_row_query() do
    DeviceConnection
    |> select([dc], %{
      device_id: dc.device_id,
      status: dc.status,
      last_seen_at: dc.last_seen_at,
      rn: row_number() |> over(partition_by: dc.device_id, order_by: [desc: dc.last_seen_at])
    })
  end

  defp distinct_on_device() do
    DeviceConnection
    |> distinct(:device_id)
    |> order_by([:device_id, desc: :last_seen_at])
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
end
