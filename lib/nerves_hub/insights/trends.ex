defmodule NervesHub.Insights.Trends do
  @moduledoc """
  How a product's fleet has moved over a period, for the trends row of the
  Insights page: which firmware it ran, how its updates went, and how much of
  it was online and healthy.

  The period is cut into buckets: hours for `"24h"`, and days in the viewer's
  time zone otherwise. The last bucket ends now, so each series ends on the
  same figures `NervesHub.Insights.composition/2` gives.

    * `updates` — finished update attempts in each bucket, split into those
      that succeeded and those that failed, as
      `NervesHub.Devices.UpdateHistory` counts them.
    * `online` — the share of the fleet connected at the end of each bucket,
      from the connection history. The last is the live figure.
    * `healthy` — the share of the fleet healthy at the end of each bucket.
      Health history keeps only transitions, and only for 90 days, so it is
      walked back from the live count: each move into healthy after a
      bucket's end is taken off, each move out of it put back.
    * `adoption` — how many devices ran each firmware version at the end of
      each bucket, walked back from the live counts the same way through the
      updates that succeeded.

  Shares are of today's fleet. A device added during the period is counted
  on its first version from the start, and one removed isn't counted at all,
  which moves a share by that device's weight and no more.

  Everything but the release reads ClickHouse, so callers check that
  analytics is enabled first.
  """

  import Ecto.Query

  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices.DeviceHealthHistory
  alias NervesHub.Devices.DeviceUpdateHistory
  alias NervesHub.Devices.UpdateHistory
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Insights
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHub.Products.Product
  alias NervesHub.Repo

  @periods %{"24h" => {:hour, 24}, "14d" => {:day, 14}, "4w" => {:day, 28}, "90d" => {:day, 90}}

  @graphed_statuses ["succeeded" | Enum.map(UpdateHistory.failure_statuses(), &Atom.to_string/1)]

  # A connection with no disconnect is still open; this stands in for "never"
  # when comparing disconnect times as integers.
  @never 9_223_372_036_854_775_807

  @typedoc "One bucket: from its start up to, not including, `until`."
  @type bucket() :: %{from: DateTime.t(), until: DateTime.t()}

  @type t() :: %{
          period: String.t(),
          unit: :hour | :day,
          time_zone: String.t(),
          now: DateTime.t(),
          total: non_neg_integer(),
          buckets: [bucket()],
          updates: [%{succeeded: non_neg_integer(), failed: non_neg_integer()}],
          online: [float()],
          healthy: [float()],
          adoption: [%{optional(String.t() | nil) => non_neg_integer()}],
          release: %{version: String.t(), at: DateTime.t()} | nil
        }

  @doc "The periods the trends row offers, shortest first."
  @spec periods() :: [String.t()]
  def periods(), do: ~w(24h 14d 4w 90d)

  @doc """
  The trends for `product` over `period` (one of `periods/0`), bucketed in
  `time_zone`, an IANA name; an unknown one falls back to UTC.

  `composition` is the product's live composition, which every series ends
  on. `release` is when the newest version was first given to a deployment
  group, or uploaded if no group has had it, when that falls in the period.
  """
  @spec trends(Product.t(), Insights.composition(), String.t(), String.t(), DateTime.t()) :: t()
  def trends(%Product{} = product, composition, period, time_zone, now \\ DateTime.utc_now()) do
    {unit, count} = Map.fetch!(@periods, period)
    {time_zone, buckets} = buckets(unit, count, time_zone, now)
    ends = Enum.map(buckets, &DateTime.to_unix(&1.until, :microsecond))
    window_start = DateTime.shift_zone!(hd(buckets).from, "Etc/UTC")

    %{
      period: period,
      unit: unit,
      time_zone: time_zone,
      now: now,
      total: composition.total,
      buckets: buckets,
      updates: updates(product, window_start, now, ends),
      online: online(product, now, ends, composition),
      healthy: healthy(product, window_start, ends, composition),
      adoption: adoption(product, window_start, now, ends, composition),
      release: release(product, composition.newest_version, window_start)
    }
  end

  defp buckets(unit, count, time_zone, now) do
    {time_zone, local_now} =
      case DateTime.shift_zone(now, time_zone) do
        {:ok, local_now} -> {time_zone, local_now}
        {:error, _} -> {"Etc/UTC", now}
      end

    starts =
      case unit do
        :hour ->
          top = %{local_now | minute: 0, second: 0, microsecond: {0, 0}}
          for back <- (count - 1)..0//-1, do: DateTime.add(top, -back * 3600, :second)

        :day ->
          today = DateTime.to_date(local_now)
          for back <- (count - 1)..0//-1, do: start_of_day(Date.add(today, -back), time_zone)
      end

    buckets = Enum.zip_with(starts, tl(starts) ++ [now], &%{from: &1, until: &2})

    {time_zone, buckets}
  end

  defp start_of_day(date, time_zone) do
    case DateTime.new(date, ~T[00:00:00], time_zone) do
      {:ok, start} -> start
      {:ambiguous, first, _second} -> first
      {:gap, _before, just_after} -> just_after
    end
  end

  # Which bucket a timestamp falls in, 1-based: the first whose end is after
  # it. 0 for one at or after the last end, which is now.
  defmacrop bucket(timestamp, ends) do
    quote do
      fragment("arrayFirstIndex(e -> toUnixTimestamp64Micro(?) < e, ?)", unquote(timestamp), unquote(ends))
    end
  end

  defp updates(product, window_start, now, ends) do
    counts =
      from(h in DeviceUpdateHistory,
        where: h.org_id == ^product.org_id and h.product_id == ^product.id,
        where: h.status in ^@graphed_statuses,
        where: h.timestamp >= ^window_start and h.timestamp < ^now,
        group_by: bucket(h.timestamp, ^ends),
        select: {
          bucket(h.timestamp, ^ends),
          %{
            succeeded: fragment("countIf(? = 'succeeded')", h.status),
            failed: fragment("countIf(? != 'succeeded')", h.status)
          }
        }
      )
      |> AnalyticsRepo.all()
      |> Map.new()

    for index <- 1..length(ends), do: Map.get(counts, index, %{succeeded: 0, failed: 0})
  end

  defp online(product, now, ends, composition) do
    # A connection has a row per change (connecting, heartbeats, the
    # disconnect), merged on its start, so take its latest disconnect time
    # without waiting for ClickHouse to merge them.
    connections =
      from(c in "device_connection_history",
        where: c.org_id == ^product.org_id and c.product_id == ^product.id,
        where: c.established_at < type(^now, :utc_datetime_usec),
        group_by: [c.device_id, c.established_at],
        select: %{
          device_id: c.device_id,
          established: fragment("toUnixTimestamp64Micro(?)", c.established_at),
          disconnected:
            fragment(
              "ifNull(toUnixTimestamp64Micro(argMax(tuple(?), ?).1), ?)",
              c.disconnected_at,
              c.version,
              ^@never
            )
        }
      )

    open =
      from(c in subquery(connections),
        where: c.disconnected > ^hd(ends),
        select: %{
          device_id: c.device_id,
          at: fragment("arrayJoin(arrayFilter(e -> ? <= e AND ? > e, ?))", c.established, c.disconnected, ^ends)
        }
      )

    counts =
      from(o in subquery(open), group_by: o.at, select: {o.at, fragment("uniqExact(?)", o.device_id)})
      |> AnalyticsRepo.all()
      |> Map.new()

    ends
    |> Enum.map(&share(Map.get(counts, &1, 0), composition.total))
    |> List.replace_at(-1, share(composition.connection.online, composition.total))
  end

  defp healthy(product, window_start, ends, composition) do
    transitions =
      from(h in DeviceHealthHistory,
        where: h.org_id == ^product.org_id and h.product_id == ^product.id,
        select: %{
          timestamp: h.timestamp,
          status: h.status,
          previous:
            fragment(
              "lagInFrame(?, 1, '') OVER (PARTITION BY ? ORDER BY ? ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)",
              h.status,
              h.device_id,
              h.timestamp
            )
        }
      )

    # How many more devices were healthy at the end of each bucket than at
    # its start.
    gains =
      from(t in subquery(transitions),
        where: t.timestamp >= ^window_start,
        group_by: bucket(t.timestamp, ^ends),
        select: {
          bucket(t.timestamp, ^ends),
          fragment("toInt64(countIf(? = 'healthy')) - toInt64(countIf(? = 'healthy'))", t.status, t.previous)
        }
      )
      |> AnalyticsRepo.all()
      |> Map.new()

    ends
    |> walk_back(composition.health.healthy, fn count, index -> count - Map.get(gains, index, 0) end)
    |> Enum.map(&share(&1, composition.total))
  end

  defp adoption(product, window_start, now, ends, composition) do
    moves =
      from(h in DeviceUpdateHistory,
        where: h.org_id == ^product.org_id and h.product_id == ^product.id,
        where: h.status == "succeeded",
        where: h.timestamp >= ^window_start and h.timestamp < ^now,
        group_by: [bucket(h.timestamp, ^ends), h.source_firmware_uuid, h.target_firmware_uuid],
        select: {bucket(h.timestamp, ^ends), h.source_firmware_uuid, h.target_firmware_uuid, fragment("count()")}
      )
      |> AnalyticsRepo.all()

    versions = firmware_versions(product, Enum.flat_map(moves, fn {_, source, target, _} -> [source, target] end))

    # Per bucket, how many devices each version gained from the updates that
    # finished in it.
    gains =
      Enum.reduce(moves, %{}, fn {index, source, target, count}, gains ->
        gains
        |> Map.update(index, %{}, & &1)
        |> update_in([index], fn by_version ->
          by_version
          |> Map.update(Map.get(versions, target), count, &(&1 + count))
          |> Map.update(Map.get(versions, source), -count, &(&1 - count))
        end)
      end)

    live = Map.new(composition.versions, &{&1.version, &1.count})

    walk_back(ends, live, fn counts, index ->
      Enum.reduce(Map.get(gains, index, %{}), counts, fn {version, gain}, counts ->
        Map.update(counts, version, max(-gain, 0), &max(&1 - gain, 0))
      end)
    end)
  end

  defp firmware_versions(product, uuids) do
    uuids = uuids |> Enum.reject(&(&1 == "")) |> Enum.uniq()

    from(f in Firmware, where: f.product_id == ^product.id and f.uuid in ^uuids, select: {f.uuid, f.version})
    |> Repo.all()
    |> Map.new()
  end

  # The value at the end of each bucket, from `live` at the end of the last:
  # each earlier one is the next with that next bucket's change undone.
  defp walk_back(ends, live, undo) do
    count = length(ends)

    {values, _} =
      Enum.map_reduce(count..1//-1, live, fn index, value ->
        {value, if(index > 1, do: undo.(value, index), else: value)}
      end)

    Enum.reverse(values)
  end

  # When the newest version was released: the first time a deployment group
  # was given it, or, for a version no group has had, when it was uploaded.
  defp release(_product, nil, _window_start), do: nil

  defp release(product, version, window_start) do
    released =
      from(r in DeploymentRelease,
        join: f in assoc(r, :firmware),
        where: f.product_id == ^product.id and f.version == ^version,
        select: min(r.inserted_at)
      )
      |> Repo.one()

    uploaded = fn ->
      from(f in Firmware, where: f.product_id == ^product.id and f.version == ^version, select: min(f.inserted_at))
      |> Repo.one()
    end

    with %NaiveDateTime{} = at <- released || uploaded.(),
         at = DateTime.from_naive!(at, "Etc/UTC"),
         true <- DateTime.compare(at, window_start) != :lt do
      %{version: version, at: at}
    else
      _ -> nil
    end
  end

  defp share(_count, 0), do: 0.0
  defp share(count, total), do: count |> max(0) |> min(total) |> Kernel./(total)
end
