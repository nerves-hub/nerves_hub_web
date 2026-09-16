defmodule NervesHub.Devices.UpdateHistory do
  @moduledoc """
  The record of how firmware update attempts ended.

  A device's update lives in `inflight_updates` while it is running and is
  deleted the moment it reaches an outcome, so nothing in PostgreSQL remembers
  that an update was ever attempted, let alone that it failed. The audit log
  carries a sentence per event, which is readable one device at a time and
  useless in aggregate — a product with a badly behaved fleet fills pages of it
  without ever saying how many updates failed this week.

  This module closes that gap, writing two things for every attempt that ends:

    * a row in `device_update_history` (ClickHouse, via
      `NervesHub.Analytics.Buffer`) — the history itself, which the Insights
      graph reads; and
    * the device's `consecutive_failed_updates` counter (PostgreSQL) — the
      current state, which the penalty box list reads.

  Two stores for one fact, as with `device_health` / `device_health_history` and
  `device_alarms` / `device_alarm_history`. The counter is not derived from the
  history because the history is analytics: it is eventually consistent, it is
  only written where `:analytics_enabled` is set, and its buffer sheds rows
  rather than block. "How many times in a row has this device failed" is an
  operational answer that has to be exact and has to exist everywhere.

  ## Statuses

  An attempt ends exactly one of six ways:

    * `:succeeded` — the device rejoined running the firmware it was sent.
    * `:failed` — the device reported an error while updating.
    * `:ignored` — the device declined the update outright.
    * `:rescheduled` — the device asked for the update to come back later.
    * `:expired` — the update stopped making progress and timed out.
    * `:abandoned` — the device rejoined still running its old firmware, with
      nothing to say about why. This is the quiet one, and on a fleet that is
      failing to update it is usually the most common: no report is sent, the
      device simply comes back as it left.

  All six are recorded. `:rescheduled` is the only one that is **not** counted
  as a failure: a device that asks for the update later is negotiating, not
  failing, and counting it would libel every product whose devices defer
  updates while they are busy. The other four all mean the device did not take
  the firmware it was sent, so `failure_statuses/0` covers them and the counter
  moves on each.
  """

  import Ecto.Query

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceUpdateHistory
  alias NervesHub.Repo

  @type status :: :succeeded | :failed | :ignored | :rescheduled | :expired | :abandoned

  @typedoc """
  What `record/3` needs of a device: enough to find its row and to scope the
  history entry.

  A `Device` struct satisfies it, and so do the partial device
  `NervesHub.FirmwareUpdates` carries and the plain map its expiry sweep builds
  out of a `DELETE ... RETURNING`.
  """
  @type device :: %{
          required(:id) => pos_integer(),
          required(:org_id) => pos_integer(),
          required(:product_id) => pos_integer(),
          optional(any()) => any()
        }

  @type bucket :: %{day: Date.t() | DateTime.t(), succeeded: non_neg_integer(), failed: non_neg_integer()}

  @statuses [:succeeded, :failed, :ignored, :rescheduled, :expired, :abandoned]
  @failure_statuses [:failed, :ignored, :expired, :abandoned]

  # The statuses the graph plots. `:rescheduled` is deliberately absent: it is a
  # deferral rather than an outcome the graph is asking about, and folding it
  # into either bar would misreport the fleet.
  @graphed_statuses [:succeeded | @failure_statuses]
  @graphed_status_names Enum.map(@graphed_statuses, &Atom.to_string/1)

  # Device reasons are free text off the wire. `DeviceTemplates` truncates them
  # to the same length before they reach an audit entry.
  @reason_max_length 200

  @doc """
  Every status an update attempt can end with.
  """
  @spec statuses() :: [status()]
  def statuses(), do: @statuses

  @doc """
  The statuses that count as the device having failed to take its firmware.

  `:rescheduled` is not one of them — see the module documentation.
  """
  @spec failure_statuses() :: [status()]
  def failure_statuses(), do: @failure_statuses

  @doc """
  Records how one firmware update attempt ended.

  Writes the history row (ClickHouse, when analytics is enabled) and moves the
  device's failure counter (PostgreSQL, always) — see the module documentation
  for why both. Callers pass whatever they hold; `device` needs only `:id`,
  `:org_id` and `:product_id`, which is what the partial device
  `NervesHub.FirmwareUpdates` works with carries.

  ## Options

    * `:deployment_id` — the deployment group that asked for the update, if any.
    * `:source_firmware_uuid` — the firmware the device was running.
    * `:target_firmware_uuid` — the firmware it was being moved to.
    * `:reason` — what the device said, where it said anything.
    * `:timestamp` — when the attempt ended, defaulting to now.

  Runs in the caller's transaction when there is one, so a rolled back outcome
  takes its counter movement with it.
  """
  @spec record(device(), status(), keyword()) :: :ok
  def record(device, status, opts \\ []) when status in @statuses do
    timestamp =
      opts
      |> Keyword.get_lazy(:timestamp, &DateTime.utc_now/0)
      # `DateTime64(6)` is `:utc_datetime_usec` to Ecto, which refuses anything
      # coarser than microseconds. Adding zero of them relabels the precision
      # without moving the instant. Worth doing rather than trusting callers:
      # a rejected row fails the whole buffer batch, so a second-precision
      # timestamp here would take unrelated rows down with it.
      |> DateTime.add(0, :microsecond)

    _ = move_counter(device, status, timestamp)

    if Application.get_env(:nerves_hub, :analytics_enabled) do
      Buffer.insert(
        DeviceUpdateHistory,
        DeviceUpdateHistory.changeset(%{
          timestamp: timestamp,
          org_id: device.org_id,
          product_id: device.product_id,
          device_id: device.id,
          deployment_id: opts[:deployment_id] || 0,
          status: Atom.to_string(status),
          source_firmware_uuid: uuid(opts[:source_firmware_uuid]),
          target_firmware_uuid: uuid(opts[:target_firmware_uuid]),
          reason: reason(opts[:reason])
        })
      )
    end

    :ok
  end

  # A success ends the run of failures, so the count goes back to zero and the
  # timestamp with it — a device that has taken firmware is not "last failed at"
  # anything. A reschedule moves neither.
  defp move_counter(device, :succeeded, _timestamp) do
    Device
    |> where(id: ^device.id)
    |> Repo.update_all(set: [consecutive_failed_updates: 0, last_update_failure_at: nil])
  end

  defp move_counter(device, status, timestamp) when status in @failure_statuses do
    Device
    |> where(id: ^device.id)
    |> Repo.update_all(
      inc: [consecutive_failed_updates: 1],
      set: [last_update_failure_at: DateTime.truncate(timestamp, :second)]
    )
  end

  defp move_counter(_device, :rescheduled, _timestamp), do: {0, nil}

  defp uuid(nil), do: ""
  defp uuid(uuid) when is_binary(uuid), do: uuid

  defp reason(nil), do: ""
  defp reason(reason) when is_binary(reason), do: String.slice(reason, 0, @reason_max_length)
  # A device is free to put anything in the reason field, including something
  # that is not a string at all, and a recorded outcome must not depend on it.
  defp reason(reason), do: reason |> inspect() |> String.slice(0, @reason_max_length)

  @doc """
  Buckets a product's finished update attempts per day, for the window
  `from..to` (both `Date`s), split into successes and failures.

  Days are bucketed in `time_zone` (an IANA name), so the bars line up with the
  viewer's calendar rather than UTC's. Every day in the window is returned (via
  a `generate_series` left join), with `0` for days nothing finished, which is
  what lets the chart draw a flat stretch rather than skipping it.

  The rows are filtered on the raw timestamp against a window widened by a day
  at each end, so ClickHouse can still prune partitions; the bucketing decides
  which day a row lands on, and the join drops anything that lands outside.
  """
  @spec update_outcomes_by_date(pos_integer(), pos_integer(), Date.t(), Date.t(), String.t()) :: [bucket()]
  def update_outcomes_by_date(org_id, product_id, %Date{} = from, %Date{} = to, time_zone) do
    window_start = DateTime.new!(Date.add(from, -1), ~T[00:00:00], "Etc/UTC")
    window_end = DateTime.new!(Date.add(to, 2), ~T[00:00:00], "Etc/UTC")

    counts =
      from h in DeviceUpdateHistory,
        where: h.org_id == ^org_id,
        where: h.product_id == ^product_id,
        where: h.status in ^@graphed_status_names,
        where: h.timestamp >= ^window_start,
        where: h.timestamp < ^window_end,
        group_by: fragment("toDate(?, ?)", h.timestamp, ^time_zone),
        select: %{
          day: fragment("toDate(?, ?)", h.timestamp, ^time_zone),
          succeeded: fragment("countIf(? = 'succeeded')", h.status),
          # Everything else is a failure: the statuses filtered in above are the
          # successes and the four failures, never a reschedule.
          failed: fragment("countIf(? != 'succeeded')", h.status)
        }

    # A row for every date in the window, so days nothing finished on come back
    # as 0 rather than being absent.
    series =
      from g in fragment(
             "generate_series(toUInt32(?), toUInt32(?), 1)",
             type(^from, :date),
             type(^to, :date)
           ),
           select: %{day_number: fragment("generate_series")}

    query =
      from s in subquery(series),
        left_join: c in subquery(counts),
        on: s.day_number == fragment("toUInt32(?)", c.day),
        order_by: s.day_number,
        select: %{
          day: fragment("toDate(?)", s.day_number),
          succeeded: fragment("coalesce(?, 0)", c.succeeded),
          failed: fragment("coalesce(?, 0)", c.failed)
        }

    AnalyticsRepo.all(query)
  end

  @doc """
  Mirrors `update_outcomes_by_date/5` at hourly granularity, for the shorter
  "last 24 hours" view.

  Hours are bucketed in `time_zone` and the `:day` key holds a zoned `DateTime`
  in that timezone — the same shape `NervesHub.Devices.Connections` returns, so
  it serialises with its offset and the browser renders it in the viewer's
  local time, consistent with the graph's bounds.
  """
  @spec update_outcomes_by_hour(pos_integer(), pos_integer(), DateTime.t(), DateTime.t(), String.t()) :: [bucket()]
  def update_outcomes_by_hour(org_id, product_id, %DateTime{} = from, %DateTime{} = to, time_zone) do
    counts =
      from h in DeviceUpdateHistory,
        where: h.org_id == ^org_id,
        where: h.product_id == ^product_id,
        where: h.status in ^@graphed_status_names,
        where: h.timestamp >= ^from,
        where: h.timestamp <= ^to,
        group_by: fragment("toStartOfHour(?, ?)", h.timestamp, ^time_zone),
        select: %{
          hour: fragment("toStartOfHour(?, ?)", h.timestamp, ^time_zone),
          succeeded: fragment("countIf(? = 'succeeded')", h.status),
          failed: fragment("countIf(? != 'succeeded')", h.status)
        }

    # An hour-start for every hour in the window, so hours nothing finished in
    # come back as 0 rather than being absent.
    series =
      from g in fragment(
             "generate_series(toUInt32(toStartOfHour(?, ?)), toUInt32(toStartOfHour(?, ?)), 3600)",
             ^from,
             ^time_zone,
             ^to,
             ^time_zone
           ),
           select: %{ts: fragment("generate_series")}

    query =
      from s in subquery(series),
        left_join: c in subquery(counts),
        on: s.ts == fragment("toUInt32(?)", c.hour),
        order_by: s.ts,
        select: %{
          day: fragment("toDateTime(?, ?)", s.ts, ^time_zone),
          succeeded: fragment("coalesce(?, 0)", c.succeeded),
          failed: fragment("coalesce(?, 0)", c.failed)
        }

    AnalyticsRepo.all(query)
  end
end
