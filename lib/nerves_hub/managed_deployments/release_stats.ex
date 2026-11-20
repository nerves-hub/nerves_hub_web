defmodule NervesHub.ManagedDeployments.ReleaseStats do
  @moduledoc """
  How a deployment group's releases went, for the group page's Stats tab.

  Each release is judged over its window: from when it was made until the next
  release replaced it, or until now for the newest. An update counts towards a
  release when the group sent it, it was moving the device to the release's
  firmware, and it ended inside the window.

  Two stores answer different questions:

    * `update_stats` (PostgreSQL) has a row for each successful update, with
      what it downloaded and what a delta saved. It was kept before the history
      below, so every release has these numbers.
    * `device_update_history` (ClickHouse) has how every attempt ended, and for
      successes since the column was added, how long it took. It is only written
      where `:analytics_enabled` is set, keeps a year, and began after some
      releases went out. `history_began/1` says from when, and `kept?/2` whether
      a release's numbers are whole.

  A duration runs from the update being sent to the device rejoining on the new
  firmware. Delta and full updates are told apart the way `update_stats` tells
  them apart: an update from a version that had a delta built is a delta
  update.
  """

  import Ecto.Query

  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices.DeviceUpdateHistory
  alias NervesHub.Devices.UpdateHistory
  alias NervesHub.Devices.UpdateStat
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareDelta
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.Repo

  @typedoc "A release and the time its numbers are counted over. `to` is nil for the newest release."
  @type window :: %{release: DeploymentRelease.t(), from: DateTime.t(), to: DateTime.t() | nil}

  @type downloads :: %{
          updated: non_neg_integer(),
          downloaded: non_neg_integer(),
          saved: non_neg_integer(),
          first_at: DateTime.t() | nil
        }

  @type outcomes :: %{
          succeeded: non_neg_integer(),
          failed: non_neg_integer(),
          rescheduled: non_neg_integer(),
          median: non_neg_integer() | nil
        }

  @typedoc """
  Where a duration falls in the Stats tab's chart: under 2 minutes, 2 to 4, 4 to
  6, 6 to 8, 8 to 10, 10 to 15, 15 to 30, and 30 or more.
  """
  @type duration_bucket :: 0..7

  @typedoc "The lower edge of a duration bucket, in seconds. Must list `[0 | @duration_edges]`."
  @type duration_bucket_start :: 0 | 120 | 240 | 360 | 480 | 600 | 900 | 1800

  @type detail :: %{
          attempts: %{succeeded: non_neg_integer(), failed: non_neg_integer(), rescheduled: non_neg_integer()},
          failed_devices: non_neg_integer(),
          recovered_devices: non_neg_integer(),
          timeline: %{
            bucket_seconds: pos_integer(),
            buckets: [{non_neg_integer(), non_neg_integer(), non_neg_integer()}]
          },
          durations: %{
            median: non_neg_integer() | nil,
            p90: non_neg_integer() | nil,
            delta_median: non_neg_integer() | nil,
            full_median: non_neg_integer() | nil,
            buckets: %{duration_bucket() => %{delta: non_neg_integer(), full: non_neg_integer()}}
          },
          reasons: [%{status: UpdateHistory.failure_status(), reason: String.t() | nil, count: pos_integer()}],
          sources: [
            %{
              uuid: String.t(),
              succeeded: non_neg_integer(),
              failed: non_neg_integer(),
              median: non_neg_integer() | nil
            }
          ]
        }

  # The upper edge of each duration bucket but the last, in seconds.
  @duration_edges [120, 240, 360, 480, 600, 900, 1800]

  # Bucket sizes for the attempts chart, smallest first. The chart takes the
  # first that fits the release's window into @max_timeline_buckets.
  @timeline_bucket_seconds [
    3600,
    2 * 3600,
    3 * 3600,
    6 * 3600,
    12 * 3600,
    86_400,
    2 * 86_400,
    7 * 86_400,
    14 * 86_400,
    30 * 86_400
  ]
  @max_timeline_buckets 48

  # Allows for the success being written to `update_stats` a moment before its
  # history row, in the same transaction.
  @kept_slack_seconds 60

  @timeout to_timeout(second: 15)

  @doc """
  Each release with its window, newest first.
  """
  @spec windows([DeploymentRelease.t()]) :: [window()]
  def windows([]), do: []

  def windows(releases) do
    oldest_first = Enum.sort_by(releases, & &1.number)
    starts = Enum.map(oldest_first, &utc(&1.inserted_at))

    oldest_first
    |> Enum.zip(starts)
    |> Enum.zip(tl(starts) ++ [nil])
    |> Enum.map(fn {{release, from}, to} -> %{release: release, from: from, to: to} end)
    |> Enum.reverse()
  end

  @doc """
  How many devices each release updated, and what they downloaded, keyed by
  release id. A release no device has taken yet is left out.

  `first_at` is when its first update ended, which `kept?/2` compares with when
  the history began.
  """
  @spec downloads_by_release(DeploymentGroup.t()) :: %{pos_integer() => downloads()}
  def downloads_by_release(%DeploymentGroup{id: id}) do
    windows =
      from(r in DeploymentRelease,
        join: f in assoc(r, :firmware),
        where: r.deployment_group_id == ^id,
        select: %{
          id: r.id,
          uuid: f.uuid,
          from: r.inserted_at,
          to: over(lead(r.inserted_at), order_by: [asc: r.number])
        }
      )

    from(s in UpdateStat,
      join: w in subquery(windows),
      on:
        s.target_firmware_uuid == fragment("?::uuid", w.uuid) and s.inserted_at >= w.from and
          (is_nil(w.to) or s.inserted_at < w.to),
      where: s.deployment_id == ^id,
      group_by: w.id,
      select:
        {w.id,
         %{
           updated: fragment("count(*)"),
           downloaded: type(coalesce(sum(s.update_bytes), 0), :integer),
           saved: type(coalesce(sum(s.saved_bytes), 0), :integer),
           first_at: min(s.inserted_at)
         }}
    )
    |> Repo.all()
    |> Map.new(fn {release_id, downloads} -> {release_id, %{downloads | first_at: utc(downloads.first_at)}} end)
  end

  @doc """
  What one release's successful updates downloaded, by the version each device
  came from and whether it took a delta.

  `source_uuid` is nil for a device that came from firmware NervesHub didn't
  know.
  """
  @spec downloads_by_source(DeploymentGroup.t(), window()) :: [
          %{
            source_uuid: String.t() | nil,
            delta?: boolean(),
            updated: pos_integer(),
            downloaded: non_neg_integer(),
            saved: non_neg_integer()
          }
        ]
  def downloads_by_source(%DeploymentGroup{id: id}, %{release: release} = window) do
    target_uuid = release_firmware_uuid(release)

    from(s in UpdateStat,
      where: s.deployment_id == ^id,
      where: s.target_firmware_uuid == ^target_uuid,
      where: s.inserted_at >= ^DateTime.to_naive(window.from),
      group_by: [s.type, s.source_firmware_uuid],
      select: %{
        source_uuid: s.source_firmware_uuid,
        delta?: s.type == "fwup_delta",
        updated: fragment("count(*)"),
        downloaded: type(coalesce(sum(s.update_bytes), 0), :integer),
        saved: type(coalesce(sum(s.saved_bytes), 0), :integer)
      }
    )
    |> naive_before(window.to)
    |> Repo.all()
  end

  defp naive_before(query, nil), do: query
  defp naive_before(query, to), do: where(query, [s], s.inserted_at < ^DateTime.to_naive(to))

  @doc """
  The deltas built for a release's firmware, keyed by the uuid of the firmware
  each starts from.
  """
  @spec deltas(DeploymentRelease.t()) :: %{String.t() => %{status: atom(), size: non_neg_integer()}}
  def deltas(%DeploymentRelease{firmware_id: firmware_id}) do
    from(fd in FirmwareDelta,
      join: f in assoc(fd, :source),
      where: fd.target_id == ^firmware_id,
      select: {f.uuid, %{status: fd.status, size: fd.size}}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  The versions of the given firmware uuids in the group's product, keyed by
  uuid. A uuid the product has no firmware for is left out.
  """
  @spec versions(DeploymentGroup.t(), [String.t()]) :: %{String.t() => String.t()}
  def versions(%DeploymentGroup{product_id: product_id}, uuids) do
    from(f in Firmware,
      where: f.product_id == ^product_id and f.uuid in ^uuids,
      select: {f.uuid, f.version}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  The workflow steps of a release that have started, in order, for marking on
  its attempts chart. `stopped?` is a step that stopped on failures.
  """
  @spec started_steps(DeploymentRelease.t()) :: [%{name: String.t(), started_at: DateTime.t(), stopped?: boolean()}]
  def started_steps(%DeploymentRelease{id: release_id}) do
    from(s in DeploymentWorkflowStep,
      where: s.deployment_release_id == ^release_id and not is_nil(s.started_at),
      order_by: s.number,
      select: %{name: s.name, started_at: s.started_at, status: s.status}
    )
    |> Repo.all()
    |> Enum.map(&%{name: &1.name, started_at: utc(&1.started_at), stopped?: &1.status == :error})
  end

  @doc """
  When the update history began for the group's product: the first outcome it
  holds, and the first with a duration. Both are nil where `:analytics_enabled`
  is not set.
  """
  @spec history_began(DeploymentGroup.t()) :: %{outcomes: DateTime.t() | nil, durations: DateTime.t() | nil}
  def history_began(%DeploymentGroup{} = deployment_group) do
    if analytics_enabled?() do
      from(h in DeviceUpdateHistory,
        where: h.org_id == ^deployment_group.org_id and h.product_id == ^deployment_group.product_id,
        select: {
          fragment("count()"),
          fragment("min(?)", h.timestamp),
          fragment("countIf(? > 0)", h.duration_seconds),
          fragment("minIf(?, ? > 0)", h.timestamp, h.duration_seconds)
        }
      )
      |> AnalyticsRepo.one(timeout: @timeout)
      |> case do
        {0, _first, _timed, _first_timed} -> %{outcomes: nil, durations: nil}
        {_count, first, 0, _first_timed} -> %{outcomes: first, durations: nil}
        {_count, first, _timed, first_timed} -> %{outcomes: first, durations: first_timed}
      end
    else
      %{outcomes: nil, durations: nil}
    end
  end

  @doc """
  Whether a release's history is whole: its first update ended after the
  history began. A release nothing has updated yet has nothing missing.
  """
  @spec kept?(DateTime.t() | nil, downloads() | nil) :: boolean()
  def kept?(_began, nil), do: true
  def kept?(_began, %{first_at: nil}), do: true
  def kept?(nil, _downloads), do: false

  def kept?(%DateTime{} = began, %{first_at: first_at}),
    do: DateTime.compare(first_at, DateTime.add(began, -@kept_slack_seconds)) != :lt

  @doc """
  How every release's attempts ended, keyed by release id, along with the
  median duration of all the group's timed updates.
  """
  @spec outcomes_by_release(DeploymentGroup.t(), [window()]) :: %{
          releases: %{pos_integer() => outcomes()},
          median: non_neg_integer() | nil
        }
  def outcomes_by_release(_deployment_group, []), do: %{releases: %{}, median: nil}

  def outcomes_by_release(%DeploymentGroup{} = deployment_group, windows) do
    oldest_first = Enum.reverse(windows)
    uuids = oldest_first |> Enum.map(&release_firmware_uuid(&1.release)) |> Enum.uniq()
    # The end of each window in microseconds, the newest's far in the future.
    ends = Enum.map(oldest_first, &if(&1.to, do: DateTime.to_unix(&1.to, :microsecond), else: 9_000_000_000_000_000))
    failures = failure_names()

    base =
      from(h in DeviceUpdateHistory,
        where: h.org_id == ^deployment_group.org_id and h.product_id == ^deployment_group.product_id,
        where: h.deployment_id == ^deployment_group.id,
        where: h.target_firmware_uuid in ^uuids,
        where: h.timestamp >= ^hd(oldest_first).from
      )

    rows =
      from(h in base,
        group_by: [
          fragment("arrayFirstIndex(e -> toUnixTimestamp64Micro(?) < e, ?)", h.timestamp, ^ends),
          h.target_firmware_uuid
        ],
        select: {
          fragment("arrayFirstIndex(e -> toUnixTimestamp64Micro(?) < e, ?)", h.timestamp, ^ends),
          h.target_firmware_uuid,
          fragment("countIf(? = 'succeeded')", h.status),
          fragment("countIf(has(?, ?))", ^failures, h.status),
          fragment("countIf(? = 'rescheduled')", h.status),
          fragment("countIf(? = 'succeeded' AND ? > 0)", h.status, h.duration_seconds),
          fragment(
            "quantileExactLowIf(0.5)(?, ? = 'succeeded' AND ? > 0)",
            h.duration_seconds,
            h.status,
            h.duration_seconds
          )
        }
      )
      |> AnalyticsRepo.all(timeout: @timeout)

    %{releases: by_release(rows, oldest_first), median: overall_median(base)}
  end

  # A row whose firmware isn't its window's release's went to a release the
  # group had before or after, a required one, and isn't counted.
  defp by_release(rows, oldest_first) do
    by_window = oldest_first |> Enum.with_index(1) |> Map.new(fn {window, index} -> {index, window.release} end)

    for {index, uuid, succeeded, failed, rescheduled, timed, median} <- rows,
        release = by_window[index],
        release && release_firmware_uuid(release) == uuid,
        into: %{} do
      {release.id, %{succeeded: succeeded, failed: failed, rescheduled: rescheduled, median: if(timed > 0, do: median)}}
    end
  end

  defp overall_median(base) do
    from(h in base,
      where: h.status == "succeeded" and h.duration_seconds > 0,
      select: {fragment("count()"), fragment("quantileExactLow(0.5)(?)", h.duration_seconds)}
    )
    |> AnalyticsRepo.one(timeout: @timeout)
    |> case do
      {0, _median} -> nil
      {_count, median} -> median
    end
  end

  @doc """
  The bucket size, in seconds, of the attempts chart for a window ending at `to`
  (or `now`, for the newest release).
  """
  @spec timeline_bucket_seconds(window(), DateTime.t()) :: pos_integer()
  def timeline_bucket_seconds(window, now) do
    span = DateTime.diff(window.to || now, window.from)

    Enum.find(@timeline_bucket_seconds, List.last(@timeline_bucket_seconds), &(span / &1 <= @max_timeline_buckets))
  end

  @doc """
  Everything the Stats tab shows of one release from the update history: how
  its attempts ended, over time and by the version devices came from, how long
  they took, and why they failed.

  `delta_sources` are the uuids of the versions devices took a delta from (see
  `downloads_by_source/2`), which split the durations into delta and full.
  """
  @spec release_detail(DeploymentGroup.t(), window(), [String.t()], DateTime.t()) :: detail()
  def release_detail(%DeploymentGroup{} = deployment_group, window, delta_sources, now \\ DateTime.utc_now()) do
    failures = failure_names()

    base =
      from(h in DeviceUpdateHistory,
        where: h.org_id == ^deployment_group.org_id and h.product_id == ^deployment_group.product_id,
        where: h.deployment_id == ^deployment_group.id,
        where: h.target_firmware_uuid == ^release_firmware_uuid(window.release),
        where: h.timestamp >= ^window.from
      )
      |> history_before(window.to)

    %{
      attempts: attempts(base),
      timeline: timeline(base, window, now)
    }
    |> Map.merge(devices(base, failures))
    |> Map.put(:durations, durations(base, delta_sources))
    |> Map.put(:reasons, reasons(base, failures))
    |> Map.put(:sources, sources(base, failures))
  end

  defp history_before(query, nil), do: query
  defp history_before(query, to), do: where(query, [h], h.timestamp < ^to)

  defp attempts(base) do
    counts =
      from(h in base, group_by: h.status, select: {h.status, fragment("count()")})
      |> AnalyticsRepo.all(timeout: @timeout)
      |> Map.new()

    failed = Enum.sum(for status <- failure_names(), do: Map.get(counts, status, 0))

    %{
      succeeded: Map.get(counts, "succeeded", 0),
      failed: failed,
      rescheduled: Map.get(counts, "rescheduled", 0)
    }
  end

  # Devices that failed at least once, and of those, how many went on to take
  # the firmware.
  defp devices(base, failures) do
    per_device =
      from(h in base,
        group_by: h.device_id,
        select: %{
          failed: fragment("countIf(has(?, ?))", ^failures, h.status),
          first_failure: fragment("minIf(?, has(?, ?))", h.timestamp, ^failures, h.status),
          last_success: fragment("maxIf(?, ? = 'succeeded')", h.timestamp, h.status),
          succeeded: fragment("countIf(? = 'succeeded')", h.status)
        }
      )

    {failed, recovered} =
      from(d in subquery(per_device),
        select: {
          fragment("countIf(? > 0)", d.failed),
          fragment("countIf(? > 0 AND ? > 0 AND ? > ?)", d.failed, d.succeeded, d.last_success, d.first_failure)
        }
      )
      |> AnalyticsRepo.one(timeout: @timeout)

    %{failed_devices: failed, recovered_devices: recovered}
  end

  defp timeline(base, window, now) do
    bucket_seconds = timeline_bucket_seconds(window, now)
    from_us = DateTime.to_unix(window.from, :microsecond)
    bucket_us = bucket_seconds * 1_000_000

    buckets =
      from(h in base,
        group_by: fragment("intDiv(toUnixTimestamp64Micro(?) - ?, ?)", h.timestamp, ^from_us, ^bucket_us),
        order_by: fragment("intDiv(toUnixTimestamp64Micro(?) - ?, ?)", h.timestamp, ^from_us, ^bucket_us),
        select: {
          fragment("intDiv(toUnixTimestamp64Micro(?) - ?, ?)", h.timestamp, ^from_us, ^bucket_us),
          fragment("countIf(? = 'succeeded')", h.status),
          fragment("countIf(has(?, ?))", ^failure_names(), h.status)
        }
      )
      |> AnalyticsRepo.all(timeout: @timeout)

    %{bucket_seconds: bucket_seconds, buckets: buckets}
  end

  defp durations(base, delta_sources) do
    timed = from(h in base, where: h.status == "succeeded" and h.duration_seconds > 0)

    buckets =
      from(h in timed,
        group_by: [
          fragment("arrayFirstIndex(e -> ? < e, ?)", h.duration_seconds, ^@duration_edges),
          fragment("has(?, ?)", ^delta_sources, h.source_firmware_uuid)
        ],
        select: {
          fragment("arrayFirstIndex(e -> ? < e, ?)", h.duration_seconds, ^@duration_edges),
          fragment("has(?, ?)", ^delta_sources, h.source_firmware_uuid),
          fragment("count()")
        }
      )
      |> AnalyticsRepo.all(timeout: @timeout)
      |> Enum.reduce(%{}, fn {index, delta, count}, acc ->
        # arrayFirstIndex is 0 past the last edge, which is the 30 minutes or more bucket
        bucket = if index == 0, do: length(@duration_edges), else: index - 1
        kind = if delta in [true, 1], do: :delta, else: :full

        acc
        |> Map.put_new(bucket, %{delta: 0, full: 0})
        |> update_in([bucket, kind], &(&1 + count))
      end)

    [count, median, p90] =
      from(h in timed,
        select: [
          fragment("count()"),
          fragment("quantileExactLow(0.5)(?)", h.duration_seconds),
          fragment("quantileExactLow(0.9)(?)", h.duration_seconds)
        ]
      )
      |> AnalyticsRepo.one(timeout: @timeout)

    by_kind =
      from(h in timed,
        group_by: fragment("has(?, ?)", ^delta_sources, h.source_firmware_uuid),
        select: {
          fragment("has(?, ?)", ^delta_sources, h.source_firmware_uuid),
          fragment("quantileExactLow(0.5)(?)", h.duration_seconds)
        }
      )
      |> AnalyticsRepo.all(timeout: @timeout)
      |> Map.new(fn {delta, median} -> {delta in [true, 1], median} end)

    %{
      median: if(count > 0, do: median),
      p90: if(count > 0, do: p90),
      delta_median: by_kind[true],
      full_median: by_kind[false],
      buckets: buckets
    }
  end

  defp reasons(base, failures) do
    from(h in base,
      where: fragment("has(?, ?)", ^failures, h.status),
      group_by: [h.status, h.reason],
      order_by: [desc: fragment("count()")],
      select: {h.status, h.reason, fragment("count()")}
    )
    |> AnalyticsRepo.all(timeout: @timeout)
    |> Enum.map(fn {status, reason, count} ->
      %{status: String.to_existing_atom(status), reason: if(reason != "", do: reason), count: count}
    end)
  end

  defp sources(base, failures) do
    from(h in base,
      group_by: h.source_firmware_uuid,
      select: {
        h.source_firmware_uuid,
        fragment("countIf(? = 'succeeded')", h.status),
        fragment("countIf(has(?, ?))", ^failures, h.status),
        fragment("countIf(? = 'succeeded' AND ? > 0)", h.status, h.duration_seconds),
        fragment(
          "quantileExactLowIf(0.5)(?, ? = 'succeeded' AND ? > 0)",
          h.duration_seconds,
          h.status,
          h.duration_seconds
        )
      }
    )
    |> AnalyticsRepo.all(timeout: @timeout)
    |> Enum.map(fn {uuid, succeeded, failed, timed, median} ->
      %{uuid: uuid, succeeded: succeeded, failed: failed, median: if(timed > 0, do: median)}
    end)
  end

  @doc """
  The lower edge of each duration bucket, in seconds.
  """
  @spec duration_bucket_starts() :: [duration_bucket_start(), ...]
  def duration_bucket_starts(), do: [0 | @duration_edges]

  @doc """
  Whether the update history is kept here at all.
  """
  @spec analytics_enabled?() :: boolean()
  def analytics_enabled?(), do: Application.get_env(:nerves_hub, :analytics_enabled, false) == true

  defp failure_names(), do: Enum.map(UpdateHistory.failure_statuses(), &Atom.to_string/1)

  defp release_firmware_uuid(%DeploymentRelease{firmware: %Firmware{uuid: uuid}}), do: uuid

  defp release_firmware_uuid(%DeploymentRelease{firmware_id: firmware_id}),
    do: Repo.one!(from(f in Firmware, where: f.id == ^firmware_id, select: f.uuid))

  defp utc(nil), do: nil
  defp utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
  defp utc(%DateTime{} = at), do: at
end
