defmodule NervesHub.Devices.Connections do
  @moduledoc """
  Handles connection data for devices, reported from device socket.
  """
  import Ecto.Query

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Repo
  alias NervesHub.Tracker

  @doc """
  Get latest inserted connection for a device.
  """
  @spec get_latest_for_device(non_neg_integer()) :: DeviceConnection.t() | nil
  def get_latest_for_device(device_id) do
    DeviceConnection
    |> where(device_id: ^device_id)
    |> Repo.one()
  end

  @doc """
  Creates a device connection, reported from device socket
  """
  @spec device_connecting(Device.t()) ::
          {:ok, DeviceConnection.t()} | {:error, Ecto.Changeset.t()}
  def device_connecting(device) do
    conflict_query =
      DeviceConnection
      |> update([ldc],
        set: [
          id: fragment("EXCLUDED.id"),
          established_at: fragment("EXCLUDED.established_at"),
          last_seen_at: fragment("EXCLUDED.last_seen_at"),
          disconnected_at: fragment("EXCLUDED.disconnected_at"),
          disconnected_reason: fragment("EXCLUDED.disconnected_reason"),
          metadata: fragment("EXCLUDED.metadata"),
          status: fragment("EXCLUDED.status")
        ]
      )

    DeviceConnection.connecting_changeset(device)
    |> Repo.insert(on_conflict: conflict_query, conflict_target: [:device_id])
    |> case do
      {:ok, device_connection} ->
        Tracker.connecting(device)

        {:ok, device_connection}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Creates a device connection, reported from device socket
  """
  @spec device_connected(Device.t(), connection_id :: binary()) :: :ok | :error
  def device_connected(device, connection_id) do
    DeviceConnection
    |> where(id: ^connection_id)
    |> where([dc], not (dc.status == :disconnected))
    |> Repo.update_all(
      set: [
        last_seen_at: DateTime.utc_now(),
        status: :connected
      ]
    )
    |> case do
      {1, _} ->
        Tracker.online(device)
        :ok

      _ ->
        :error
    end
  end

  @doc """
  Updates the `last_seen_at`field for a device connection with current timestamp
  """
  @spec device_heartbeat(Device.t(), UUIDv7.t()) :: :ok | :error
  def device_heartbeat(device, id) do
    DeviceConnection
    |> where([dc], dc.id == ^id)
    |> where([dc], not (dc.status == :disconnected))
    |> Repo.update_all(
      set: [
        status: :connected,
        last_seen_at: DateTime.utc_now()
      ]
    )
    |> case do
      {1, _} ->
        Tracker.heartbeat(device)
        :ok

      _ ->
        :error
    end
  end

  @doc """
  Updates `status` and relevant timestamps for a device connection record,
  and stores the reason for disconnection if provided.
  """
  @spec device_disconnected(Device.t(), UUIDv7.t(), String.t() | nil) :: :ok | {:error, any()}
  def device_disconnected(device, ref_id, reason \\ nil) do
    now = DateTime.utc_now()

    DeviceConnection
    |> where(id: ^ref_id)
    |> Repo.update_all(
      set: [
        last_seen_at: now,
        disconnected_at: now,
        disconnected_reason: reason,
        status: :disconnected
      ]
    )
    |> case do
      {1, _} ->
        Tracker.offline(device)
        :ok

      res ->
        {:error, res}
    end
  end

  @doc """
  Updates the connection `metadata` by merging in new metadata.
  """
  @spec merge_update_metadata(UUIDv7.t(), map()) :: :ok | :error
  def merge_update_metadata(ref_id, new_metadata) do
    DeviceConnection
    |> where(id: ^ref_id)
    |> update([dc], set: [metadata: fragment("? || ?::jsonb", dc.metadata, ^new_metadata)])
    |> Repo.update_all([])
    |> case do
      {1, _} -> :ok
      _ -> :error
    end
  end

  def clean_stale_connections() do
    interval = Application.get_env(:nerves_hub, :device_last_seen_update_interval_minutes)
    jitter = Application.get_env(:nerves_hub, :device_last_seen_update_interval_jitter_seconds)
    update_limit = Application.get_env(:nerves_hub, :device_connection_update_limit)

    max_jitter = ceil(jitter / 60)
    some_time_ago = DateTime.shift(DateTime.utc_now(), minute: -(interval + max_jitter + 1))
    now = DateTime.utc_now()

    query =
      DeviceConnection
      |> where(status: :connected)
      |> where([d], d.last_seen_at < ^some_time_ago)
      |> select([dc], dc.id)
      |> limit(^update_limit)
      |> order_by(:last_seen_at)

    {update_count, _} =
      DeviceConnection
      |> where([d], d.id in subquery(query))
      |> Repo.update_all(
        [
          set: [
            status: :disconnected,
            disconnected_at: now,
            disconnected_reason: "Stale connection"
          ]
        ],
        timeout: 60_000
      )

    if update_count > 0 do
      :telemetry.execute([:nerves_hub, :devices, :stale_connections], %{count: update_count})
    end

    if update_count < update_limit do
      :ok
    else
      # relax stress on Ecto pool and go again
      Process.sleep(2000)
      clean_stale_connections()
    end
  end
end
