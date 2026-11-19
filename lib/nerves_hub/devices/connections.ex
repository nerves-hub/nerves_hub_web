defmodule NervesHub.Devices.Connections do
  @moduledoc """
  Handles connection data for devices, reported from device socket.
  """
  import Ecto.Query

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices
  alias NervesHub.Devices.ClientLibrary
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.DeviceConnectionHistory
  alias NervesHub.Integrations
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias NervesHub.Tracker
  alias NervesHub.Webhooks.Payloads

  @doc """
  Whether `device` has connected but its last connection is older than any
  connection record: it is provisioned, which its first connection does, and
  `connection`, its row in `latest_device_connections`, is nil.

  That table started empty when it replaced `device_connections`, and every
  connection since writes a row, so these devices last connected before it
  existed. They count as last seen long ago (the `last_seen <` filter matches
  them) rather than as never connected, and pages show their last seen as
  unknown.
  """
  @spec last_seen_unrecorded?(Device.t(), DeviceConnection.t() | nil) :: boolean()
  def last_seen_unrecorded?(%Device{status: :provisioned}, nil), do: true
  def last_seen_unrecorded?(_device, _connection), do: false

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

  Replaces the device's previous connection row. Nothing carries over from it:
  `ip_address` and the client library (`lib` / `lib_version`, from
  `client_library`) are recorded as unknown when left out.

  A device often reconnects before the server has noticed its old socket is
  gone. If the previous connection is still open, it is closed as of its
  `last_seen_at` with the reason `"Reconnected"`, because once the row is
  replaced neither its socket's `device_disconnected/2` nor
  `clean_stale_connections/0` can find it. Its `device.disconnected` event
  goes out only if it had reached `:connected`.
  """
  @spec device_connecting(
          pos_integer(),
          pos_integer(),
          pos_integer(),
          String.t() | nil,
          ClientLibrary.t()
        ) :: {:ok, DeviceConnection.t()} | {:error, Ecto.Changeset.t()}
  def device_connecting(
        org_id,
        product_id,
        device_id,
        ip_address \\ nil,
        client_library \\ %{lib: nil, lib_version: nil}
      ) do
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
          network_interface: fragment("EXCLUDED.network_interface"),
          ip_address: fragment("EXCLUDED.ip_address")
        ]
      )

    changeset = DeviceConnection.connecting_changeset(org_id, product_id, device_id, ip_address, client_library)

    # The lock makes two connects for the same device take turns, so each
    # replaced connection is closed once.
    Repo.transact(fn ->
      previous =
        DeviceConnection
        |> where(device_id: ^device_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      with {:ok, device_connection} <-
             Repo.insert(changeset, on_conflict: conflict_query, conflict_target: [:device_id]) do
        {:ok, {previous, device_connection}}
      end
    end)
    |> case do
      {:ok, {previous, device_connection}} ->
        :ok = close_replaced_connection(previous)

        async_device_connection_history_insert(device_connection)

        Tracker.connecting(device_id)

        {:ok, device_connection}

      {:error, _} = error ->
        error
    end
  end

  defp close_replaced_connection(nil), do: :ok
  defp close_replaced_connection(%DeviceConnection{status: :disconnected}), do: :ok

  defp close_replaced_connection(%DeviceConnection{} = previous) do
    closed = %{
      previous
      | status: :disconnected,
        disconnected_at: previous.last_seen_at,
        disconnected_reason: "Reconnected"
    }

    async_device_connection_history_insert(closed)

    # A connection still `:connecting` never raised `device.connected`, so it
    # raises no disconnect either.
    if previous.status == :connected do
      Integrations.dispatch(closed.product_id, "device.disconnected", fn ->
        Payloads.device_disconnected(closed)
      end)
    else
      :ok
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

        :ok =
          Integrations.dispatch(device_connection.product_id, "device.connected", fn ->
            Payloads.device_connected(device_connection)
          end)

      _ ->
        :error
    end
  end

  @doc """
  Updates the `last_seen_at`field for a device connection with current timestamp
  """
  @spec device_heartbeat(Ecto.UUID.t()) :: :ok | :error
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
  @spec device_disconnected(Ecto.UUID.t(), String.t() | nil) :: :ok | {:error, any()}
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

        :ok =
          Integrations.dispatch(device_connection.product_id, "device.disconnected", fn ->
            Payloads.device_disconnected(device_connection)
          end)

      res ->
        {:error, res}
    end
  end

  defp async_device_connection_history_insert(device_connections) when is_list(device_connections) do
    Enum.each(device_connections, &async_device_connection_history_insert/1)
  end

  defp async_device_connection_history_insert(%DeviceConnection{} = device_connection) do
    device_connection
    |> DeviceConnectionHistory.from_device_connection_changeset()
    |> async_device_connection_history_insert()
  end

  # Every connection event for every device lands here, so the write is batched
  # rather than sent as its own INSERT. The `ReplacingMergeTree` collapses a
  # connection's rows by `version`, not by arrival order, so it does not matter
  # which batch each one rides in.
  defp async_device_connection_history_insert(%Ecto.Changeset{data: %DeviceConnectionHistory{}} = device_connection) do
    if Application.get_env(:nerves_hub, :analytics_enabled) do
      Buffer.insert(DeviceConnectionHistory, device_connection)
    else
      :ok
    end
  end

  @spec update_network_interface(binary(), atom()) :: {:ok, DeviceConnection.t()} | :error
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

      _ ->
        :error
    end
  end

  @doc """
  Updates the connection `metadata` by merging in new metadata.
  """
  @spec merge_update_metadata(Ecto.UUID.t(), map()) :: :ok | {:error, any()}
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

          :ok = dispatch_stale_disconnects(device_connections)

          results
      end

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

  # A swept connection never went through `device_disconnected/2`, so this is
  # the only place its disconnect is raised. A node that crashed or was cut off
  # leaves all of its connections to this sweep, so a batch can be large: the
  # device lookups are one query per product with a subscribed integration,
  # and none for products without one.
  defp dispatch_stale_disconnects(device_connections) do
    device_connections
    |> Enum.group_by(& &1.product_id)
    |> Enum.filter(fn {product_id, _connections} -> Integrations.subscribed?(product_id, "device.disconnected") end)
    |> Enum.each(fn {product_id, connections} ->
      devices = connections |> Enum.map(& &1.device_id) |> Payloads.devices()

      Enum.each(connections, fn connection ->
        :ok =
          Integrations.dispatch(product_id, "device.disconnected", fn ->
            Payloads.device_disconnected(connection, devices)
          end)
      end)
    end)
  end

  @doc """
  Writes a disconnected history row for every connection ClickHouse still
  has open but that hasn't been seen within the stale window.

  A safety net, run hourly by `NervesHub.Workers.CleanStaleDeviceConnectionHistory`.
  `clean_stale_connections/0` already writes a history row for each
  connection it closes, and `device_connecting/5` for each one a reconnect
  replaces, so this only finds disconnects that were lost before
  reaching ClickHouse, such as rows still buffered in
  `NervesHub.Analytics.Buffer` when a node died. It is kept off the
  every-minute sweep because the query is a `FINAL` scan of the whole
  `device_connection_history` table. Does nothing unless analytics is enabled.
  """
  @spec clean_stale_connections_from_analytics() :: :ok
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

  @doc """
  How many times the device disconnected during each of two trailing
  windows, as `{count_in_first, count_in_second}` — one query for both.

  Backs the "disconnects" built-in health profile metric (a warning and an
  alert window per judgement); callers are expected to check that analytics
  is enabled first.
  """
  @spec disconnection_counts(pos_integer(), pos_integer(), pos_integer(), {pos_integer(), pos_integer()}) ::
          {non_neg_integer(), non_neg_integer()}
  def disconnection_counts(org_id, product_id, device_id, {first_seconds, second_seconds}) do
    now = DateTime.utc_now()
    first_cutoff = DateTime.shift(now, second: -first_seconds)
    second_cutoff = DateTime.shift(now, second: -second_seconds)
    widest = if DateTime.before?(first_cutoff, second_cutoff), do: first_cutoff, else: second_cutoff

    DeviceConnectionHistory
    |> where([dc], dc.org_id == ^org_id and dc.product_id == ^product_id and dc.device_id == ^device_id)
    |> where([dc], not is_nil(dc.disconnected_at))
    |> where([dc], dc.disconnected_at >= ^widest)
    |> select(
      [dc],
      {fragment("countIf(disconnected_at >= ?)", ^first_cutoff),
       fragment("countIf(disconnected_at >= ?)", ^second_cutoff)}
    )
    |> AnalyticsRepo.one(settings: [final: 1])
  end

  # A gap between connections shorter than this is a reconnect, not time
  # offline worth showing.
  @shortest_offline_seconds 60

  @doc """
  The spans between `from` and `until` when the device had no connection, as
  `[{from, until}]`, oldest first, read from the connection history.

  A connection with no `disconnected_at` is taken to still be open. Gaps under
  a minute are left out. Callers are expected to check that analytics is
  enabled first.
  """
  @spec offline_periods(
          %{id: pos_integer(), org_id: pos_integer(), product_id: pos_integer()},
          DateTime.t(),
          DateTime.t()
        ) :: [{DateTime.t(), DateTime.t()}]
  def offline_periods(%{id: device_id, org_id: org_id, product_id: product_id}, from, until) do
    DeviceConnectionHistory
    |> where([dc], dc.org_id == ^org_id and dc.product_id == ^product_id and dc.device_id == ^device_id)
    |> where([dc], dc.established_at <= ^until)
    |> where([dc], is_nil(dc.disconnected_at) or dc.disconnected_at >= ^from)
    |> select([dc], {dc.established_at, dc.disconnected_at})
    |> AnalyticsRepo.all(settings: [final: 1])
    |> offline_gaps(from, until)
  end

  @doc """
  The gaps between `from` and `until` that `connections` don't cover, oldest
  first.

  `connections` is `[{established_at, disconnected_at | nil}]`, in any order
  and possibly overlapping; a nil `disconnected_at` is still open. Gaps under
  a minute are left out.
  """
  @spec offline_gaps([{DateTime.t(), DateTime.t() | nil}], DateTime.t(), DateTime.t()) ::
          [{DateTime.t(), DateTime.t()}]
  def offline_gaps(connections, from, until) do
    {covered_to, gaps} =
      connections
      |> Enum.map(fn {established_at, disconnected_at} -> {established_at, disconnected_at || until} end)
      |> Enum.sort_by(&elem(&1, 0), DateTime)
      |> Enum.reduce({from, []}, fn {established_at, disconnected_at}, {covered_to, gaps} ->
        {latest(covered_to, disconnected_at), add_gap(gaps, covered_to, established_at)}
      end)

    gaps
    |> add_gap(covered_to, until)
    |> Enum.reverse()
  end

  defp add_gap(gaps, start, stop) do
    if DateTime.diff(stop, start) >= @shortest_offline_seconds, do: [{start, stop} | gaps], else: gaps
  end

  defp latest(a, b), do: if(DateTime.after?(b, a), do: b, else: a)

  def flapping_connections(%Product{} = product) do
    DeviceConnectionHistory
    |> where([dc], dc.org_id == ^product.org_id and dc.product_id == ^product.id)
    |> where([dc], dc.established_at >= fragment("now() - INTERVAL 1 HOUR"))
    |> select([dc], %{device_id: dc.device_id, count: fragment("count() as count")})
    |> group_by([dc], dc.device_id)
    |> having([dc], fragment("count > 10"))
    |> order_by(desc: fragment("count"))
    |> AnalyticsRepo.all(settings: [final: 1])
    |> Devices.with_counts(product)
  end
end
