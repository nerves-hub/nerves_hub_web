defmodule NervesHub.Devices.Connections do
  @moduledoc """
  Handles connection data for devices, reported from device socket.
  """
  import Ecto.Query

  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.DeviceConnectionHistory
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
  @spec device_connecting(pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, DeviceConnection.t()} | {:error, Ecto.Changeset.t()}
  def device_connecting(org_id, product_id, device_id) do
    conflict_query =
      DeviceConnection
      |> update([ldc],
        set: [
          id: fragment("EXCLUDED.id"),
          org_id: fragment("EXCLUDED.org_id"),
          product_id: fragment("EXCLUDED.product_id"),
          established_at: fragment("EXCLUDED.established_at"),
          last_seen_at: fragment("EXCLUDED.last_seen_at"),
          disconnected_at: fragment("EXCLUDED.disconnected_at"),
          disconnected_reason: fragment("EXCLUDED.disconnected_reason"),
          metadata: fragment("EXCLUDED.metadata"),
          status: fragment("EXCLUDED.status"),
          lib: fragment("EXCLUDED.lib"),
          lib_version: fragment("EXCLUDED.lib_version"),
          network_interface: fragment("EXCLUDED.network_interface")
        ]
      )

    DeviceConnection.connecting_changeset(org_id, product_id, device_id)
    |> Repo.insert(on_conflict: conflict_query, conflict_target: [:device_id])
    |> case do
      {:ok, device_connection} ->
        async_device_connection_history_insert(device_connection)

        Tracker.connecting(device_id)

        {:ok, device_connection}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Creates a device connection, reported from device socket
  """
  @spec device_connected(connection_id :: binary()) :: :ok | :error
  def device_connected(connection_id) do
    DeviceConnection
    |> where(id: ^connection_id)
    |> where([dc], not (dc.status == :disconnected))
    |> select([dc], dc)
    |> Repo.update_all(
      set: [
        last_seen_at: DateTime.utc_now(),
        status: :connected
      ]
    )
    |> case do
      {1, [%{device_id: device_id} = device_connection]} ->
        async_device_connection_history_insert(device_connection)

        Tracker.online(device_id)

        :ok

      _ ->
        :error
    end
  end

  @doc """
  Updates the `last_seen_at`field for a device connection with current timestamp
  """
  @spec device_heartbeat(UUIDv7.t()) :: :ok | :error
  def device_heartbeat(id) do
    DeviceConnection
    |> where([dc], dc.id == ^id)
    |> where([dc], not (dc.status == :disconnected))
    |> select([dc], dc)
    |> Repo.update_all(
      set: [
        status: :connected,
        last_seen_at: DateTime.utc_now()
      ]
    )
    |> case do
      {1, [%{device_id: device_id} = device_connection]} ->
        async_device_connection_history_insert(device_connection)

        Tracker.heartbeat(device_id)

        :ok

      _ ->
        :error
    end
  end

  @doc """
  Updates `status` and relevant timestamps for a device connection record,
  and stores the reason for disconnection if provided.
  """
  @spec device_disconnected(UUIDv7.t(), String.t() | nil) :: :ok | {:error, any()}
  def device_disconnected(ref_id, reason \\ nil) do
    now = DateTime.utc_now()

    DeviceConnection
    |> where(id: ^ref_id)
    |> select([dc], dc)
    |> Repo.update_all(
      set: [
        last_seen_at: now,
        disconnected_at: now,
        disconnected_reason: reason,
        status: :disconnected
      ]
    )
    |> case do
      {1, [%{device_id: device_id} = device_connection]} ->
        async_device_connection_history_insert(device_connection)

        Tracker.offline(device_id)

        :ok

      res ->
        {:error, res}
    end
  end

  defp async_device_connection_history_insert(device_connections) when is_list(device_connections) do
    if Application.get_env(:nerves_hub, :analytics_enabled) do
      Enum.each(device_connections, fn device_connection ->
        async_device_connection_history_insert(device_connection)
      end)
    end

    :ok
  end

  defp async_device_connection_history_insert(%DeviceConnection{} = device_connection) do
    device_connection
    |> DeviceConnectionHistory.from_device_connection_changeset()
    |> async_device_connection_history_insert()
  end

  defp async_device_connection_history_insert(%Ecto.Changeset{data: %DeviceConnectionHistory{}} = device_connection) do
    _ =
      if Application.get_env(:nerves_hub, :analytics_enabled) do
        Task.Supervisor.start_child(
          {:via, PartitionSupervisor, {NervesHub.AnalyticsEventsProcessing, self()}},
          fn ->
            {:ok, _} =
              NervesHub.AnalyticsRepo.insert(device_connection)
          end
        )
      end

    :ok
  end

  def update_network_interface(ref_id, network_interface) do
    humanized = DeviceConnection.humanized_network_interface_name(network_interface)

    DeviceConnection
    |> where(id: ^ref_id)
    |> select([dc], dc)
    |> update([dc], set: [network_interface: ^humanized])
    |> Repo.update_all([])
    |> case do
      {1, [device_connection]} ->
        async_device_connection_history_insert(device_connection)
        {:ok, device_connection}

      res ->
        {:error, res}
    end
  end

  @doc """
  Updates the connection `metadata` by merging in new metadata.
  """
  @spec merge_update_metadata(UUIDv7.t(), map()) :: :ok | {:error, any()}
  def merge_update_metadata(ref_id, new_metadata) do
    DeviceConnection
    |> where(id: ^ref_id)
    |> update([dc], set: [metadata: fragment("? || ?::jsonb", dc.metadata, ^new_metadata)])
    |> Repo.update_all([])
    |> case do
      {1, _} -> :ok
      result -> {:error, result}
    end
  end

  def device_connections_by_date(org_id, product_id, from) do
    window_start = Date.add(from, -1)
    window_end = Date.utc_today()

    inner =
      from c in "device_connection_history",
        where: c.org_id == ^org_id,
        where: c.product_id == ^product_id,
        where: c.established_at < fragment("? + 1", type(^window_end, :date)),
        where: is_nil(c.disconnected_at) or c.disconnected_at >= type(^window_start, :date),
        select: %{
          device_id: c.device_id,
          day:
            fragment(
              "toDate(arrayJoin(range(toUInt32(greatest(toDate(?), ?)), toUInt32(least(coalesce(toDate(?), ?), ?)) + 1)))",
              c.established_at,
              type(^window_start, :date),
              c.disconnected_at,
              type(^window_end, :date),
              type(^window_end, :date)
            )
        }

    query =
      from s in subquery(inner),
        group_by: s.day,
        order_by: s.day,
        select: %{
          day: s.day,
          count: fragment("uniqExact(?)", s.device_id)
        }

    NervesHub.AnalyticsRepo.all(query)
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
      |> where([dc], dc.id in subquery(query))
      |> select([dc], dc)
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
      |> case do
        {_count, device_connections} = results ->
          async_device_connection_history_insert(device_connections)

          results
      end

    if update_count > 0 do
      :telemetry.execute([:nerves_hub, :devices, :stale_connections], %{count: update_count})
    end

    if update_count < update_limit do
      # Once the DB is cleaned, we can clean Analytics
      clean_stale_connections_from_analytics()
    else
      # relax stress on Ecto pool and go again
      Process.sleep(2000)
      clean_stale_connections()
    end
  end

  def clean_stale_connections_from_analytics() do
    _ =
      if Application.get_env(:nerves_hub, :analytics_enabled) do
        interval = Application.get_env(:nerves_hub, :device_last_seen_update_interval_minutes)
        jitter = Application.get_env(:nerves_hub, :device_last_seen_update_interval_jitter_seconds)

        max_jitter = ceil(jitter / 60)
        some_time_ago = DateTime.shift(DateTime.utc_now(), minute: -(interval + max_jitter + 1))

        DeviceConnectionHistory
        |> where([dc], is_nil(dc.disconnected_at))
        |> where([d], d.last_seen_at < ^some_time_ago)
        |> select([dc], dc)
        |> NervesHub.AnalyticsRepo.all(settings: [final: 1])
        |> Enum.each(fn connection ->
          connection
          |> DeviceConnectionHistory.mark_as_stale_and_disconnected_changeset()
          |> async_device_connection_history_insert()
        end)
      end

    :ok
  end
end
