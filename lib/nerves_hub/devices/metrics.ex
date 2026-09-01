defmodule NervesHub.Devices.Metrics do
  @moduledoc """
  Device metrics: what a device reports about itself, and what is kept of it.

  Readings are written to ClickHouse as `NervesHub.Devices.DeviceMetric`, via
  `NervesHub.Analytics.Buffer`, and read back for the health tab's charts. The
  latest set of each device is denormalised into PostgreSQL as
  `NervesHub.Devices.DeviceLatestMetrics`, because the devices list has to filter
  on it alongside the rest of a device's state in one query.

  ClickHouse rows carry the firmware the device was running, so a metric can be
  read per release. The PostgreSQL row does not: the latest set is always
  "now", and what the device is running now is on the device row, one join
  away in the same database.

  Every write goes through `record/3`, whichever extension it arrived on, so
  the caps below apply once rather than once per client.

  ## What a report may carry

  Metric names come from the device, and they land in three places that a
  confused client could widen permanently: a `LowCardinality` column in
  ClickHouse, JSONB keys in PostgreSQL, and the advanced-query autosuggest list
  a product's operators read. So a report is trimmed rather than trusted:

    * Names longer than 64 bytes are dropped.
    * At most `:max_keys_per_report` names are kept (20 by default, configurable
      — see `config/config.exs`), taken in sorted order so a device over the
      limit loses the same readings every report rather than an arbitrary
      subset that changes shape between them.
    * Values that are not numbers are dropped.

  In each case the rest of the report is stored — a device that gets one metric
  wrong should not lose the reading it got right — and the operator is told
  through `NervesHub.ProductNotifications`, throttled per device by
  `NervesHub.RateLimit.Metrics` so a permanently broken client costs one
  notification a minute rather than one per report.
  """

  import Ecto.Query

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceLatestMetrics
  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.ProductNotifications
  alias NervesHub.RateLimit.Metrics, as: RateLimit
  alias NervesHub.Repo

  @max_key_bytes 64
  @default_max_keys_per_report 20

  # One notification per device per minute, whatever the report. The budget is
  # per device rather than per product: a single broken device in a large fleet
  # should not stop its neighbours' problems being reported.
  @rate_limit_tokens_per_sec 1
  @rate_limit_max_capacity 1
  @rate_limit_token_cost 1

  @default_metrics [
    "cpu_temp",
    "cpu_usage_percent",
    "disk_available_kb",
    "disk_total_kb",
    "disk_used_percentage",
    "load_15min",
    "load_1min",
    "load_5min",
    "mem_size_mb",
    "mem_used_mb",
    "mem_used_percent"
  ]

  def default_metrics(), do: @default_metrics

  @doc """
  A device's readings of one metric over `time_frame`, oldest first.

  `time_frame` is a `{unit, amount}` pair, e.g. `{"hour", 3}`.

  Takes the device rather than its id because the ClickHouse table is sorted
  `(product_id, device_id, key, timestamp)` -- without the product this would
  read every part in every partition instead of one range of one.

  An empty list where the deployment has no ClickHouse. Metric *history* is the
  one thing that needs one; the latest set is in PostgreSQL, so the device page
  still has numbers to show.
  """
  @spec get_device_metrics_by_key(Device.t(), String.t(), {String.t(), pos_integer()}) :: [DeviceMetric.t()]
  def get_device_metrics_by_key(%Device{} = device, key, {time_unit, amount}) do
    if Application.get_env(:nerves_hub, :analytics_enabled) do
      since = DateTime.add(DateTime.utc_now(), -amount, String.to_existing_atom(time_unit))

      DeviceMetric
      |> where(product_id: ^device.product_id)
      |> where(device_id: ^device.id)
      |> where(key: ^key)
      |> where([m], m.timestamp > ^since)
      |> order_by(asc: :timestamp)
      |> AnalyticsRepo.all()
    else
      []
    end
  end

  @doc """
  Distinct metric keys reported by devices in the product, sorted.

  Taken from the latest row per device rather than from the history: it feeds
  the advanced-query autosuggest list, which wants the names a product currently
  reports, and one row per device is a small fraction of one row per reading.
  """
  @spec distinct_keys(pos_integer()) :: [String.t()]
  def distinct_keys(product_id) do
    DeviceLatestMetrics
    |> where(product_id: ^product_id)
    |> select([m], fragment("jsonb_object_keys(?)", m.metrics))
    |> distinct(true)
    |> Repo.all()
    |> Enum.sort()
  end

  @doc """
  The device's most recent readings, keyed by metric name, plus a `"timestamp"`.

  Reads the denormalised `device_latest_metrics` row rather than the history, so
  it costs one primary-key lookup and works whether or not this deployment has a
  ClickHouse. An empty map when the device has never reported.
  """
  @spec get_latest_metric_set(pos_integer()) :: map()
  def get_latest_metric_set(device_id) do
    case Repo.get(DeviceLatestMetrics, device_id) do
      nil -> %{}
      %DeviceLatestMetrics{metrics: metrics, reported_at: reported_at} -> Map.put(metrics, "timestamp", reported_at)
    end
  end

  @doc """
  The device's raw readings for `keys` over the trailing window, as
  `[{key, timestamp, value}]` — what health evaluation judges. ClickHouse:
  callers are expected to check that analytics is enabled first.
  """
  def samples_since(device_id, keys, seconds) do
    cutoff = DateTime.shift(DateTime.utc_now(), second: -seconds)

    DeviceMetric
    |> where([dm], dm.device_id == ^device_id)
    |> where([dm], dm.key in ^keys)
    |> where([dm], dm.timestamp > ^cutoff)
    |> select([dm], {dm.key, dm.timestamp, dm.value})
    |> AnalyticsRepo.all()
  end

  @doc """
  The longest metric name that will be stored, in bytes.
  """
  def max_key_bytes(), do: @max_key_bytes

  @doc """
  How many metrics one report may carry.
  """
  @spec max_keys_per_report() :: pos_integer()
  def max_keys_per_report() do
    :nerves_hub
    |> Application.get_env(:device_metrics, [])
    |> Keyword.get(:max_keys_per_report, @default_max_keys_per_report)
  end

  @doc """
  Records one report of metrics from one device.

  `timestamp` is when the device took the readings. It defaults to now, which is
  what `NervesHub.Extensions.Health` wants: a 0.0.1 report carries no timestamp
  of its own, so the only one available is the moment it arrived.

  Returns how many readings were stored, which is not necessarily how many were
  sent — see the module documentation for what gets trimmed and why.
  """
  @spec record(DeviceInfo.t(), map(), DateTime.t()) :: {:ok, non_neg_integer()}
  def record(device_info, metrics, timestamp \\ DateTime.utc_now())

  def record(%DeviceInfo{}, metrics, _timestamp) when map_size(metrics) == 0, do: {:ok, 0}

  def record(%DeviceInfo{} = device_info, metrics, %DateTime{} = timestamp) do
    timestamp = with_microsecond_precision(timestamp)

    readings =
      metrics
      |> Enum.flat_map(&normalize/1)
      |> reject_oversized_keys(device_info)
      |> cap_key_count(device_info)

    :ok = write_analytics(device_info, readings, timestamp)
    :ok = write_latest(device_info, readings, timestamp)

    {:ok, length(readings)}
  end

  # Both PostgreSQL columns are `:utc_datetime_usec`, and the rows are written
  # with `insert_all`/`insert!`, which dump straight to the database rather than
  # casting -- so a `DateTime` carrying anything less than microsecond precision
  # is rejected. Devices and callers hand over whatever precision they happen to
  # have, so it is padded here, once, and the same value goes to all three
  # stores.
  defp with_microsecond_precision(%DateTime{microsecond: {value, _precision}} = timestamp) do
    %{timestamp | microsecond: {value, 6}}
  end

  # `{key, value}` as the device sent it, into `{key, float}` or nothing.
  #
  # Spaces are stripped rather than rejected, which is what the PostgreSQL
  # schema did before this and what devices in the field are written against.
  # A non-numeric value is dropped silently: unlike an over-long name it is a
  # single bad reading rather than a client that will keep doing it, and the
  # health tab has always simply not drawn it.
  defp normalize({key, value}) when is_binary(key) do
    case to_float(value) do
      {:ok, float} -> [{String.replace(key, " ", ""), float}]
      :error -> []
    end
  end

  defp normalize(_pair), do: []

  defp to_float(value) when is_float(value), do: {:ok, value}
  defp to_float(value) when is_integer(value), do: {:ok, value * 1.0}
  defp to_float(_value), do: :error

  defp reject_oversized_keys(readings, device_info) do
    {kept, oversized} = Enum.split_with(readings, fn {key, _value} -> byte_size(key) <= @max_key_bytes end)

    _ =
      case oversized do
        [] ->
          :ok

        [{example, _value} | _rest] ->
          notify(device_info, fn ->
            ProductNotifications.create_oversized_metric_keys_notification!(
              device_info,
              example,
              length(oversized),
              @max_key_bytes
            )
          end)
      end

    kept
  end

  defp cap_key_count(readings, device_info) do
    max_keys = max_keys_per_report()

    if length(readings) <= max_keys do
      readings
    else
      _ =
        notify(device_info, fn ->
          ProductNotifications.create_too_many_metrics_notification!(device_info, length(readings), max_keys)
        end)

      # Sorted before the cap, so the same readings survive every report. Taking
      # whatever the map happened to enumerate first would give a chart that
      # stops and starts for no reason the operator can see.
      readings
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.take(max_keys)
    end
  end

  # Both notifications cost a PostgreSQL upsert and a broadcast, and a client
  # that gets this wrong gets it wrong on every report forever. The dedup on
  # `{product_id, event_key}` keeps the table from growing; this keeps the
  # writes off the metrics path.
  defp notify(device_info, build) do
    case RateLimit.hit(
           "device_#{device_info.device_id}",
           @rate_limit_tokens_per_sec,
           @rate_limit_max_capacity,
           @rate_limit_token_cost
         ) do
      {:allow, _count} ->
        _ = build.()
        :ok

      {:deny, _ms} ->
        :ok
    end
  end

  defp write_analytics(_device_info, [], _timestamp), do: :ok

  # `Buffer.insert/2` is a cast to a named process, and the buffers are only
  # started where there is a ClickHouse to write to. Gated explicitly rather
  # than relying on a cast to a missing name quietly succeeding, so that a
  # deployment without analytics is a decision this code made.
  defp write_analytics(device_info, readings, timestamp) do
    if Application.get_env(:nerves_hub, :analytics_enabled) do
      firmware_uuid = firmware_uuid(device_info)

      Enum.each(readings, fn {key, value} ->
        Buffer.insert(
          DeviceMetric,
          DeviceMetric.changeset(%{
            timestamp: timestamp,
            org_id: device_info.org_id,
            product_id: device_info.product_id,
            device_id: device_info.device_id,
            key: key,
            value: value,
            firmware_uuid: firmware_uuid
          })
        )
      end)
    end

    :ok
  end

  # Read from the connection rather than asked for, because the device does not
  # send it and does not need to: `DeviceInfo` carries the firmware the device
  # reported on join, and it is refreshed when the device reports new metadata,
  # so it is right for as long as the connection lives. A firmware update
  # reboots the device, which is a new connection.
  #
  # Empty string for a device that has not reported firmware metadata, matching
  # `NervesHub.ErrorReports`. `LowCardinality` has no null to speak of, and an
  # empty string groups as its own bucket rather than pretending to be a
  # release.
  defp firmware_uuid(%DeviceInfo{firmware_metadata: %{uuid: uuid}}) when is_binary(uuid), do: uuid
  defp firmware_uuid(_device_info), do: ""

  defp write_latest(_device_info, [], _timestamp), do: :ok

  # Replaces the device's row outright rather than merging into it: the latest
  # set is what one report said, and a key the device has stopped reporting
  # should stop being shown rather than linger at whatever it last was.
  #
  # The `WHERE` on the upsert is what makes an out-of-order report harmless. A
  # batched report can carry readings older than ones already stored -- a device
  # that buffered across a disconnect sends them on reconnect -- and without
  # this the last message to arrive would win rather than the latest reading.
  defp write_latest(device_info, readings, timestamp) do
    row = %{
      device_id: device_info.device_id,
      product_id: device_info.product_id,
      metrics: Map.new(readings),
      reported_at: timestamp
    }

    on_conflict =
      DeviceLatestMetrics
      |> update([m],
        set: [metrics: fragment("EXCLUDED.metrics"), reported_at: fragment("EXCLUDED.reported_at")]
      )
      |> where([m], fragment("EXCLUDED.reported_at") >= m.reported_at)

    # `insert_all` rather than `insert!`: the `WHERE` above means the upsert
    # writes no row when the report is older than what is stored, and `insert!`
    # reads that as an `Ecto.StaleEntryError`. Declining the write is the whole
    # point of the clause, so it has to be an ordinary outcome -- which for
    # `insert_all` is a count of zero.
    {_written, nil} = Repo.insert_all(DeviceLatestMetrics, [row], on_conflict: on_conflict, conflict_target: :device_id)

    :ok
  end
end
