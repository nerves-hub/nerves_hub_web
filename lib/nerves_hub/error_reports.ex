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

    * `:status` — `:unresolved`, `:resolved`, `:muted`, or `nil` for all.
    * `:search` — matches the reason, case-insensitively.
    * `:sort` — `:last_seen` (default), `:first_seen` or `:count`.
    * `:page` / `:page_size`.
  """
  @spec groups_for_product(Product.t(), keyword()) :: {[ErrorGroup.t()], Flop.Meta.t()}
  def groups_for_product(%Product{} = product, opts \\ []) do
    flop = %Flop{
      page: Keyword.get(opts, :page, 1),
      page_size: Keyword.get(opts, :page_size, @default_limit)
    }

    ErrorGroup
    |> where([g], g.product_id == ^product.id)
    |> filter_status(Keyword.get(opts, :status))
    |> filter_search(Keyword.get(opts, :search))
    |> sort_groups(Keyword.get(opts, :sort, :last_seen))
    |> Flop.run(flop)
  end

  @doc """
  How many issues a product has in each status.

  One grouped query rather than three counts, since the page shows all of them
  side by side.
  """
  @spec status_counts(Product.t()) :: %{atom() => non_neg_integer()}
  def status_counts(%Product{} = product) do
    counts =
      ErrorGroup
      |> where([g], g.product_id == ^product.id)
      |> group_by([g], g.status)
      |> select([g], {g.status, count(g.id)})
      |> Repo.all()
      |> Map.new()

    Map.new(ErrorGroup.statuses(), &{&1, Map.get(counts, &1, 0)})
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

  defp filter_search(query, search) do
    where(query, [g], ilike(g.reason, ^"%#{escape_like(search)}%"))
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

    * `:device_id` — only this device's.
    * `:before` — strictly before this time, so the oldest row on a page can be
      handed straight back as the next page's cursor without repeating itself.
    * `:limit`.
  """
  @spec occurrences(ErrorGroup.t(), keyword()) :: [ErrorReport.t()]
  def occurrences(%ErrorGroup{} = group, opts \\ []) do
    ErrorReport
    |> where([r], r.product_id == ^group.product_id and r.fingerprint == ^group.fingerprint)
    |> filter_device(Keyword.get(opts, :device_id))
    |> filter_before(Keyword.get(opts, :before))
    |> order_by([r], desc: r.timestamp)
    |> limit(^Keyword.get(opts, :limit, @default_limit))
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
  The devices an issue has been seen on, most recently first.

  Devices deleted since their occurrences were recorded are dropped — ClickHouse
  keeps the id, PostgreSQL is where it means something.
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
      |> order_by([r], desc: max(r.timestamp))
      |> limit(^Keyword.get(opts, :limit, @default_limit))
      |> AnalyticsRepo.all()

    devices =
      Device
      |> where([d], d.id in ^Enum.map(aggregates, & &1.device_id))
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    Enum.flat_map(aggregates, fn aggregate ->
      case Map.fetch(devices, aggregate.device_id) do
        {:ok, device} -> [aggregate |> Map.delete(:device_id) |> Map.put(:device, device)]
        :error -> []
      end
    end)
  end

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
  """
  @spec reopen(ErrorGroup.t()) :: {:ok, ErrorGroup.t()} | {:error, Ecto.Changeset.t()}
  def reopen(%ErrorGroup{} = group) do
    group
    |> ErrorGroup.reopen_changeset()
    |> Repo.update()
  end
end
