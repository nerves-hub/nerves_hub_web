defmodule NervesHub.ErrorReports do
  @moduledoc """
  Exceptions and errors reported by devices, grouped into issues.

  Two stores, joined by a fingerprint:

    * `NervesHub.ErrorReports.ErrorGroup` in PostgreSQL — one row per distinct
      error per product. Mutable, bounded, and what the product page lists.
    * `NervesHub.ErrorReports.ErrorReport` in ClickHouse — one row per
      occurrence, at fleet scale, dropped after thirty days.

  The write path fans out to both. The read paths are deliberately asymmetric:
  anything that lists reaches for PostgreSQL, anything that drills into one
  issue reaches for ClickHouse. See `docs/error_reports.md` for why the split
  falls where it does.
  """

  import Ecto.Query

  alias NervesHub.Accounts.User
  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.PubSub
  alias NervesHub.ErrorReports.ErrorGroup
  alias NervesHub.ErrorReports.ErrorReport
  alias NervesHub.ErrorReports.Fingerprint
  alias NervesHub.ErrorReports.GroupBuffer
  alias NervesHub.ErrorReports.Payload
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHub.Products.Product
  alias NervesHub.Repo

  @default_limit 25
  @device_window_days 30

  @typedoc """
  One row of the device tab: a group, plus what is true of it *on that device*.

  `device_occurrence_count` is not `group.occurrence_count` — the first is this
  device's share, the second is the whole fleet's. Keeping them apart is the
  point of the struct.
  """
  @type device_group() :: %{
          group: ErrorGroup.t(),
          device_occurrence_count: non_neg_integer(),
          last_seen_at: DateTime.t()
        }

  # --------------------------------------------------------------- write path

  @doc """
  Records a batch of reports from one device.

  Reports that cannot be read are skipped rather than failing their neighbours:
  a device that gets one report wrong should not lose the rest of the second it
  crashed in. Returns how many were stored.
  """
  @spec record_batch(DeviceInfo.t(), [map()]) :: {:ok, non_neg_integer()}
  def record_batch(%DeviceInfo{} = device_info, reports) when is_list(reports) do
    stored = Enum.count(reports, &match?({:ok, _occurrence}, record(device_info, &1)))

    {:ok, stored}
  end

  @doc """
  Records one report from one device.
  """
  @spec record(DeviceInfo.t(), map()) :: {:ok, ErrorReport.t()} | {:error, atom()}
  def record(%DeviceInfo{} = device_info, report) do
    with {:ok, attrs} <- Payload.normalize(report) do
      attrs = identify(attrs, device_info)
      row = occurrence_attrs(attrs)
      occurrence = struct(ErrorReport, row)

      _ = Buffer.insert(ErrorReport, ErrorReport.changeset(row))
      :ok = GroupBuffer.record(attrs)
      _ = PubSub.broadcast(device_info.device_id, "error_reports:received", occurrence)

      {:ok, occurrence}
    end
  end

  # The device's own `firmware_uuid` wins when it sends one, because it knows
  # what it was actually running; the connection's metadata is the fallback for
  # clients that do not bother. `for_report/1` is called while `:fingerprint`
  # still holds whatever the device supplied — it is what decides whether that
  # key is used — so the resolved hash is written over it afterwards, never
  # before.
  defp identify(attrs, device_info) do
    attrs
    |> Map.put(:org_id, device_info.org_id)
    |> Map.put(:product_id, device_info.product_id)
    |> Map.put(:device_id, device_info.device_id)
    |> Map.update!(:firmware_uuid, fn
      "" -> firmware_uuid(device_info)
      uuid -> uuid
    end)
    |> then(&Map.put(&1, :fingerprint, Fingerprint.for_report(&1)))
    |> Map.put(:fingerprint_version, Fingerprint.version())
  end

  defp firmware_uuid(%DeviceInfo{firmware_metadata: %{uuid: uuid}}) when is_binary(uuid), do: uuid
  defp firmware_uuid(_device_info), do: ""

  # A plain map rather than a struct: the buffer needs a changeset and the
  # broadcast needs a struct, and `Map.from_struct/1` would hand the changeset
  # `:__meta__` along with the fields.
  defp occurrence_attrs(attrs) do
    %{
      timestamp: attrs.timestamp,
      org_id: attrs.org_id,
      product_id: attrs.product_id,
      device_id: attrs.device_id,
      fingerprint: attrs.fingerprint,
      kind: attrs.kind,
      source: attrs.source,
      reason: attrs.reason,
      message: attrs.message,
      frames: encode_frames(attrs.frames),
      context: attrs.context,
      firmware_uuid: attrs.firmware_uuid,
      payload_bytes: attrs.payload_bytes,
      truncated: attrs.truncated
    }
  end

  # Frames are strings and integers by the time `Payload` is done with them, so
  # this cannot realistically fail — but an occurrence is worth storing without
  # its stacktrace, and not worth losing over one.
  defp encode_frames(frames) do
    case Jason.encode(frames) do
      {:ok, encoded} -> encoded
      {:error, _reason} -> "[]"
    end
  end

  # --------------------------------------------------------- product read path

  @doc """
  A product's issues, paginated.

  ## Options

    * `:status`: `:unresolved`, `:resolved`, `:muted`, or `nil` for all.
    * `:search`: matches the reason or the top frame's module and function,
      case-insensitively.
    * `:firmware`: a firmware version; only issues last seen on it.
    * `:sort`: `:last_seen` (default), `:first_seen` or `:count`.
    * `:page` / `:page_size`.

  Preloads `:resolved_by` and `:muted_by`, which the rows show.
  """
  @spec groups_for_product(Product.t(), keyword()) :: {[ErrorGroup.t()], Flop.Meta.t()}
  def groups_for_product(%Product{} = product, opts \\ []) do
    flop = %Flop{
      page: Keyword.get(opts, :page, 1),
      page_size: Keyword.get(opts, :page_size, @default_limit)
    }

    product
    |> filtered_groups(opts)
    |> filter_status(Keyword.get(opts, :status))
    |> sort_groups(Keyword.get(opts, :sort, :last_seen))
    |> preload([:resolved_by, :muted_by])
    |> Flop.run(flop)
  end

  @doc """
  How many issues a product has in each status.

  One grouped query rather than three counts, since the page shows all of them
  side by side. Takes the same `:search` and `:firmware` options as
  `groups_for_product/2`, so a search that finds nothing on one tab can say
  where its matches are.
  """
  @spec status_counts(Product.t(), keyword()) :: %{atom() => non_neg_integer()}
  def status_counts(%Product{} = product, opts \\ []) do
    counts =
      product
      |> filtered_groups(opts)
      |> group_by([g], g.status)
      |> select([g], {g.status, count(g.id)})
      |> Repo.all()
      |> Map.new()

    Map.new(ErrorGroup.statuses(), &{&1, Map.get(counts, &1, 0)})
  end

  defp filtered_groups(product, opts) do
    ErrorGroup
    |> where([g], g.product_id == ^product.id)
    |> filter_search(Keyword.get(opts, :search))
    |> filter_firmware(product, Keyword.get(opts, :firmware))
  end

  @doc """
  When the most recent resolve in a product happened, or `nil` if nothing in
  it is resolved.
  """
  @spec last_resolved_at(Product.t()) :: DateTime.t() | nil
  def last_resolved_at(%Product{} = product) do
    ErrorGroup
    |> where([g], g.product_id == ^product.id and g.status == :resolved)
    |> select([g], max(g.resolved_at))
    |> Repo.one()
  end

  @doc """
  The firmware versions a product's issues were last seen on, newest upload
  first, for the list's firmware filter.
  """
  @spec last_seen_versions(Product.t()) :: [String.t()]
  def last_seen_versions(%Product{} = product) do
    ErrorGroup
    |> join(:inner, [g], f in Firmware, on: f.uuid == g.last_seen_firmware_uuid and f.product_id == g.product_id)
    |> where([g], g.product_id == ^product.id)
    |> group_by([_g, f], f.version)
    |> order_by([_g, f], desc: max(f.inserted_at))
    |> select([_g, f], f.version)
    |> Repo.all()
  end

  @doc """
  The firmware each of `uuids` names in a product, as `%{uuid => %{version:,
  deleted?:}}`.

  A report carries only its firmware's UUID. A UUID with no firmware behind it
  (the product never had it, or the row is gone) is left out, so callers can
  tell it apart from one that is merely deleted.
  """
  @spec firmware_by_uuid(Product.t(), [String.t() | nil]) :: %{
          String.t() => %{version: String.t(), deleted?: boolean()}
        }
  def firmware_by_uuid(%Product{} = product, uuids) do
    uuids = uuids |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq()

    Firmware
    |> where([f], f.product_id == ^product.id and f.uuid in ^uuids)
    # A UUID can be uploaded again after a delete; the live row wins.
    |> order_by([f], asc: not is_nil(f.deleted_at), desc: f.inserted_at)
    |> select([f], {f.uuid, %{version: f.version, deleted?: not is_nil(f.deleted_at)}})
    |> Repo.all()
    |> Enum.reverse()
    |> Map.new()
  end

  @doc """
  When `version` of a product's firmware was first released, and to which
  deployment group, or `nil` if no group has been given it.
  """
  @spec first_release(Product.t(), String.t() | nil) ::
          %{version: String.t(), at: DateTime.t(), deployment_group: String.t()} | nil
  def first_release(_product, nil), do: nil

  def first_release(%Product{} = product, version) do
    DeploymentRelease
    |> join(:inner, [r], f in assoc(r, :firmware))
    |> join(:inner, [r], dg in assoc(r, :deployment_group))
    |> where([_r, f], f.product_id == ^product.id and f.version == ^version)
    |> order_by([r], asc: r.inserted_at)
    |> limit(1)
    |> select([r, _f, dg], %{version: ^version, at: r.inserted_at, deployment_group: dg.name})
    |> Repo.one()
    |> case do
      nil -> nil
      release -> Map.update!(release, :at, &DateTime.from_naive!(&1, "Etc/UTC"))
    end
  end

  @doc """
  How many unresolved issues each of `product_ids` has, in one query. A
  product with none is left out.
  """
  @spec unresolved_counts_by_product([pos_integer()]) :: %{pos_integer() => pos_integer()}
  def unresolved_counts_by_product([]), do: %{}

  def unresolved_counts_by_product(product_ids) do
    ErrorGroup
    |> where([g], g.product_id in ^product_ids and g.status == :unresolved)
    |> group_by([g], g.product_id)
    |> select([g], {g.product_id, count(g.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  One issue, scoped to its product.

  Scoped rather than fetched by id alone: an id is guessable, and a group from
  another organisation's product is not this caller's to read.
  """
  @spec get_group!(Product.t(), integer() | String.t()) :: ErrorGroup.t()
  def get_group!(%Product{} = product, id) do
    # Preloaded in the query rather than through `Repo.preload/2`, which is
    # typed to take and return either a struct or a list of them and so widens
    # this function's return type to include both.
    ErrorGroup
    |> where([g], g.product_id == ^product.id and g.id == ^id)
    |> preload([:resolved_by, :muted_by])
    |> Repo.one!()
  end

  defp filter_status(query, nil), do: query
  defp filter_status(query, :all), do: query
  defp filter_status(query, status), do: where(query, [g], g.status == ^status)

  defp filter_search(query, nil), do: query
  defp filter_search(query, ""), do: query

  # The top frame is searched as `Module.function`, the way the list shows it,
  # so "Poller.handle_info" finds a frame stored as module and function apart.
  defp filter_search(query, search) do
    pattern = "%#{escape_like(search)}%"

    where(
      query,
      [g],
      ilike(g.reason, ^pattern) or
        ilike(fragment("concat_ws('.', ?, ?)", g.top_frame_module, g.top_frame_function), ^pattern)
    )
  end

  defp filter_firmware(query, _product, nil), do: query
  defp filter_firmware(query, _product, ""), do: query

  defp filter_firmware(query, product, version) do
    uuids = from(f in Firmware, where: f.product_id == ^product.id and f.version == ^version, select: f.uuid)

    where(query, [g], g.last_seen_firmware_uuid in subquery(uuids))
  end

  # `%` and `_` are wildcards to `ilike`, and a reason is full of neither by
  # accident — a device logging "100%" should be found by searching for "100%".
  defp escape_like(search) do
    String.replace(search, ~r/([\\%_])/, "\\\\\\1")
  end

  defp sort_groups(query, :count), do: order_by(query, [g], desc: g.occurrence_count)
  defp sort_groups(query, :first_seen), do: order_by(query, [g], desc: g.first_seen_at)
  defp sort_groups(query, _last_seen), do: order_by(query, [g], desc: g.last_seen_at)

  # ---------------------------------------------------------- device read path

  @doc """
  How many issues one device has reported in the window `groups_for_device/2`
  reads, for the count beside the device page's Errors tab.

  Counts fingerprints in ClickHouse alone, so unlike `groups_for_device/2` it
  includes the rare fingerprint whose group row is gone.
  """
  @spec issue_count_for_device(Device.t()) :: non_neg_integer()
  def issue_count_for_device(%Device{} = device) do
    since = DateTime.add(DateTime.utc_now(), -@device_window_days, :day)

    ErrorReport
    |> where([r], r.product_id == ^device.product_id)
    |> where([r], r.device_id == ^device.id)
    |> where([r], r.timestamp >= ^since)
    |> select([r], fragment("uniqExact(?)", r.fingerprint))
    |> AnalyticsRepo.one()
    |> Kernel.||(0)
  end

  @doc """
  The issues seen on one device, most recently seen first.

  Reads the aggregate from ClickHouse and the names from PostgreSQL. A
  fingerprint with occurrences but no group row — the group was deleted, or the
  fingerprint algorithm moved on — is dropped rather than rendered half-built.
  """
  @spec groups_for_device(Device.t(), keyword()) :: [device_group()]
  def groups_for_device(%Device{} = device, opts \\ []) do
    since = Keyword.get(opts, :since, DateTime.add(DateTime.utc_now(), -@device_window_days, :day))
    limit = Keyword.get(opts, :limit, @default_limit)

    aggregates =
      ErrorReport
      |> where([r], r.product_id == ^device.product_id)
      |> where([r], r.device_id == ^device.id)
      |> where([r], r.timestamp >= ^since)
      |> group_by([r], r.fingerprint)
      |> select([r], %{
        fingerprint: r.fingerprint,
        device_occurrence_count: count(r.fingerprint),
        last_seen_at: max(r.timestamp)
      })
      |> order_by([r], desc: max(r.timestamp))
      |> limit(^limit)
      |> AnalyticsRepo.all()

    groups = groups_by_fingerprint(device.product_id, Enum.map(aggregates, & &1.fingerprint))

    Enum.flat_map(aggregates, fn aggregate ->
      case Map.fetch(groups, aggregate.fingerprint) do
        {:ok, group} -> [Map.put(aggregate, :group, group)]
        :error -> []
      end
    end)
  end

  defp groups_by_fingerprint(_product_id, []), do: %{}

  defp groups_by_fingerprint(product_id, fingerprints) do
    ErrorGroup
    |> where([g], g.product_id == ^product_id and g.fingerprint in ^fingerprints)
    |> Repo.all()
    |> Map.new(&{&1.fingerprint, &1})
  end

  # ------------------------------------------------------------- drill-downs

  @doc """
  Occurrences of one issue, newest first.

  ## Options

    * `:device_id`: only this device's.
    * `:before`: strictly before this time, so the oldest row on a page can be
      handed straight back as the next page's cursor without repeating itself.
    * `:limit`.
    * `:offset`: skip this many of the newest first, for paging through
      them one at a time.
  """
  @spec occurrences(ErrorGroup.t(), keyword()) :: [ErrorReport.t()]
  def occurrences(%ErrorGroup{} = group, opts \\ []) do
    ErrorReport
    |> where([r], r.product_id == ^group.product_id and r.fingerprint == ^group.fingerprint)
    |> filter_device(Keyword.get(opts, :device_id))
    |> filter_before(Keyword.get(opts, :before))
    |> order_by([r], desc: r.timestamp)
    |> limit(^Keyword.get(opts, :limit, @default_limit))
    |> offset(^Keyword.get(opts, :offset, 0))
    |> AnalyticsRepo.all()
  end

  @doc """
  The most recent occurrence of an issue, or `nil` once they have aged out.

  A group outlives its occurrences by design, so `nil` here means "older than
  the retention window", not "something went wrong".
  """
  @spec latest_occurrence(ErrorGroup.t(), keyword()) :: ErrorReport.t() | nil
  def latest_occurrence(%ErrorGroup{} = group, opts \\ []) do
    group
    |> occurrences(Keyword.put(opts, :limit, 1))
    |> List.first()
  end

  @doc """
  How many distinct devices an issue has been seen on, within the retained window.
  """
  @spec affected_device_count(ErrorGroup.t()) :: non_neg_integer()
  def affected_device_count(%ErrorGroup{} = group) do
    ErrorReport
    |> where([r], r.product_id == ^group.product_id and r.fingerprint == ^group.fingerprint)
    |> select([r], fragment("uniqExact(?)", r.device_id))
    |> AnalyticsRepo.one()
    |> Kernel.||(0)
  end

  @doc """
  The devices an issue has been seen on, most recently first, or with the
  most occurrences first when `order: :count` is given.

  Devices deleted or moved to another product since their occurrences were
  recorded are dropped. ClickHouse keeps the id and the product it was
  reported under; PostgreSQL is where the device lives now.
  """
  @spec affected_devices(ErrorGroup.t(), keyword()) :: [
          %{device: Device.t(), occurrence_count: non_neg_integer(), last_seen_at: DateTime.t()}
        ]
  def affected_devices(%ErrorGroup{} = group, opts \\ []) do
    aggregates =
      ErrorReport
      |> where([r], r.product_id == ^group.product_id and r.fingerprint == ^group.fingerprint)
      |> group_by([r], r.device_id)
      |> select([r], %{
        device_id: r.device_id,
        occurrence_count: count(r.device_id),
        last_seen_at: max(r.timestamp)
      })
      |> order_devices(Keyword.get(opts, :order, :last_seen))
      |> limit(^Keyword.get(opts, :limit, @default_limit))
      |> AnalyticsRepo.all()

    devices =
      Device
      |> where([d], d.product_id == ^group.product_id and d.id in ^Enum.map(aggregates, & &1.device_id))
      |> preload(:latest_connection)
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    Enum.flat_map(aggregates, fn aggregate ->
      case Map.fetch(devices, aggregate.device_id) do
        {:ok, device} -> [aggregate |> Map.delete(:device_id) |> Map.put(:device, device)]
        :error -> []
      end
    end)
  end

  defp order_devices(query, :count), do: order_by(query, [r], desc: count(r.device_id), desc: max(r.timestamp))
  defp order_devices(query, _last_seen), do: order_by(query, [r], desc: max(r.timestamp))

  @doc """
  Occurrences of an issue bucketed by day, in the viewer's timezone.

  Every day in the window comes back, including the quiet ones — a chart that
  simply omits its empty days draws a line straight through them.

  The zero-filling is done here rather than with a `generate_series` join. Dates
  and datetimes are different things to ClickHouse, `toUInt32` of a `Date` is a
  day number rather than a second, and a window is at most a few hundred days —
  which makes this the version that is both correct and readable.
  """
  @spec occurrences_by_date(ErrorGroup.t(), Date.t(), Date.t(), String.t()) :: [map()]
  def occurrences_by_date(%ErrorGroup{} = group, %Date{} = from, %Date{} = to, time_zone) do
    counts =
      from(r in ErrorReport,
        where: r.product_id == ^group.product_id,
        where: r.fingerprint == ^group.fingerprint,
        where: fragment("toDate(?, ?)", r.timestamp, ^time_zone) >= ^from,
        where: fragment("toDate(?, ?)", r.timestamp, ^time_zone) <= ^to,
        group_by: fragment("toDate(?, ?)", r.timestamp, ^time_zone),
        select: %{
          date: fragment("toDate(?, ?)", r.timestamp, ^time_zone),
          count: count(r.fingerprint),
          device_count: fragment("uniqExact(?)", r.device_id)
        }
      )
      |> AnalyticsRepo.all()
      |> Map.new(&{&1.date, &1})

    from
    |> Date.range(to)
    |> Enum.map(fn date ->
      Map.get(counts, date, %{date: date, count: 0, device_count: 0})
    end)
  end

  @doc """
  Occurrences of an issue bucketed by whole UTC hours, from the hour `from`
  falls in to the hour `to` does.

  Like `occurrences_by_date/4`, every hour comes back, quiet ones included.
  There is no time zone here, unlike the daily buckets: a zone half or three
  quarters of an hour off UTC would start its hours somewhere else. The
  caller shifts each hour to local time for its label.
  """
  @spec occurrences_by_hour(ErrorGroup.t(), DateTime.t(), DateTime.t()) :: [map()]
  def occurrences_by_hour(%ErrorGroup{} = group, %DateTime{} = from, %DateTime{} = to) do
    from = truncate_to_hour(from)
    to = truncate_to_hour(to)

    counts =
      from(r in ErrorReport,
        where: r.product_id == ^group.product_id,
        where: r.fingerprint == ^group.fingerprint,
        where: r.timestamp >= ^from,
        where: r.timestamp < ^DateTime.add(to, 1, :hour),
        group_by: fragment("toStartOfHour(?)", r.timestamp),
        select: %{hour: fragment("toStartOfHour(?)", r.timestamp), count: count(r.fingerprint)}
      )
      |> AnalyticsRepo.all()
      |> Map.new(&{&1.hour |> to_utc_datetime() |> DateTime.to_unix(), &1.count})

    from
    |> Stream.iterate(&DateTime.add(&1, 1, :hour))
    |> Enum.take_while(&(DateTime.compare(&1, to) != :gt))
    |> Enum.map(&%{hour: &1, count: Map.get(counts, DateTime.to_unix(&1), 0)})
  end

  defp truncate_to_hour(%DateTime{} = at), do: %{DateTime.truncate(at, :second) | minute: 0, second: 0}

  # `toStartOfHour` comes back as a naive datetime or a datetime, depending on
  # the column type; both name the same instant in UTC.
  defp to_utc_datetime(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
  defp to_utc_datetime(%DateTime{} = at), do: at

  @doc """
  How many of an issue's occurrences are still kept. Lower than
  `occurrence_count` once any have aged out.
  """
  @spec retained_count(ErrorGroup.t()) :: non_neg_integer()
  def retained_count(%ErrorGroup{} = group) do
    ErrorReport
    |> where([r], r.product_id == ^group.product_id and r.fingerprint == ^group.fingerprint)
    |> select([r], count(r.fingerprint))
    |> AnalyticsRepo.one()
    |> Kernel.||(0)
  end

  @doc """
  An issue's kept occurrences split by the firmware they were reported on,
  most first, as `%{firmware_uuid:, count:, device_count:}`.

  At most `:limit` firmware come back. A device names the firmware its
  reports were sent from, so there is no telling how many there are.
  """
  @spec occurrences_by_firmware(ErrorGroup.t(), keyword()) :: [map()]
  def occurrences_by_firmware(%ErrorGroup{} = group, opts \\ []) do
    ErrorReport
    |> where([r], r.product_id == ^group.product_id and r.fingerprint == ^group.fingerprint)
    |> group_by([r], r.firmware_uuid)
    |> select([r], %{
      firmware_uuid: r.firmware_uuid,
      count: count(r.fingerprint),
      device_count: fragment("uniqExact(?)", r.device_id)
    })
    |> order_by([r], desc: count(r.fingerprint))
    |> limit(^Keyword.get(opts, :limit, @default_limit))
    |> AnalyticsRepo.all()
  end

  @doc """
  The sparkline and device count the issues list shows for `groups`, from ClickHouse.

  Two queries. Returns `%{fingerprint => %{daily: [non_neg_integer()], device_count: n}}`,
  where `daily` covers the last `days` days oldest first with quiet days as zero
  and `device_count` is how many devices have kept occurrences. A fingerprint
  with nothing kept is absent.
  """
  @spec list_stats(Product.t(), [ErrorGroup.t()], pos_integer(), String.t()) :: %{String.t() => map()}
  def list_stats(_product, [], _days, _time_zone), do: %{}

  def list_stats(%Product{} = product, groups, days, time_zone) do
    fingerprints = Enum.map(groups, & &1.fingerprint)
    today = time_zone |> DateTime.now!() |> DateTime.to_date()
    first_day = Date.add(today, 1 - days)

    daily =
      from(r in ErrorReport,
        where: r.product_id == ^product.id and r.fingerprint in ^fingerprints,
        where: fragment("toDate(?, ?)", r.timestamp, ^time_zone) >= ^first_day,
        group_by: [r.fingerprint, fragment("toDate(?, ?)", r.timestamp, ^time_zone)],
        select: {r.fingerprint, fragment("toDate(?, ?)", r.timestamp, ^time_zone), count(r.fingerprint)}
      )
      |> AnalyticsRepo.all()
      |> Enum.group_by(&elem(&1, 0), &{elem(&1, 1), elem(&1, 2)})

    devices =
      from(r in ErrorReport,
        where: r.product_id == ^product.id and r.fingerprint in ^fingerprints,
        group_by: r.fingerprint,
        select: {r.fingerprint, fragment("uniqExact(?)", r.device_id)}
      )
      |> AnalyticsRepo.all()
      |> Map.new()

    dates = Date.range(first_day, today)

    Map.new(devices, fn {fingerprint, device_count} ->
      by_date = daily |> Map.get(fingerprint, []) |> Map.new()
      {fingerprint, %{daily: Enum.map(dates, &Map.get(by_date, &1, 0)), device_count: device_count}}
    end)
  end

  defp filter_device(query, nil), do: query
  defp filter_device(query, device_id), do: where(query, [r], r.device_id == ^device_id)

  defp filter_before(query, nil), do: query
  defp filter_before(query, %DateTime{} = before), do: where(query, [r], r.timestamp < ^before)

  # ---------------------------------------------------------------- lifecycle

  @doc """
  Marks an issue resolved.

  `firmware_uuid` names the release the fix is expected to be in. Nothing reads
  it yet — see `NervesHub.ErrorReports.ErrorGroup.resolve_changeset/3`.
  """
  @spec resolve(ErrorGroup.t(), User.t(), String.t() | nil) ::
          {:ok, ErrorGroup.t()} | {:error, Ecto.Changeset.t()}
  def resolve(%ErrorGroup{} = group, %User{} = user, firmware_uuid \\ nil) do
    group
    |> ErrorGroup.resolve_changeset(user, firmware_uuid)
    |> Repo.update()
  end

  @doc """
  Silences an issue without claiming it is fixed.
  """
  @spec mute(ErrorGroup.t(), User.t()) :: {:ok, ErrorGroup.t()} | {:error, Ecto.Changeset.t()}
  def mute(%ErrorGroup{} = group, %User{} = user) do
    group
    |> ErrorGroup.mute_changeset(user)
    |> Repo.update()
  end

  @doc """
  Returns an issue to the queue, from either resolved or muted.

  `opts` is for undo: `:regressed_at` puts back the regression a resolve
  cleared, and `:resolved_at`, `:resolved_by_id` and
  `:resolved_in_firmware_uuid` put back an earlier resolve that a regression
  left on the issue, which a plain reopen would clear. Undoing a resolve or a
  mute then leaves the issue as it was rather than as a plain unresolved one.
  """
  @spec reopen(ErrorGroup.t(), keyword()) :: {:ok, ErrorGroup.t()} | {:error, Ecto.Changeset.t()}
  def reopen(%ErrorGroup{} = group, opts \\ []) do
    group
    |> ErrorGroup.reopen_changeset(opts)
    |> Repo.update()
  end
end
