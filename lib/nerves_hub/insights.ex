defmodule NervesHub.Insights do
  @moduledoc """
  What a product's fleet is made of, for the product Insights page.

  `composition/2` counts every device in a product once by connection, by
  health and by the firmware version it last reported, and crosses health and
  connection with firmware version. `versions/1` folds that into the rows the
  page shows, and `stands_out/1` picks out a version whose devices are
  notably less healthy than the rest of the fleet.

  Everything here reads PostgreSQL alone, so the page shows it whether or not
  the deployment runs analytics.

  The groupings follow the devices list's filters, so a count here matches
  the list it links to:

    * connection: online (`connection = "connected"`); offline and last seen
      in the last 7 days; last seen 7 to 14 days ago; last seen over 14 days
      ago (`connection=not_seen_in_fourteen_days`); and never connected.
    * health: healthy, warning, unhealthy and unknown, where a device that has
      never reported its health counts as unknown, as the `health_status`
      filter treats it.
    * not healthy: warning, unhealthy or unknown, the devices
      `health_status != "healthy"` matches.
  """

  import Ecto.Query

  alias NervesHub.Devices.Device
  alias NervesHub.Products.Product
  alias NervesHub.Repo

  @typedoc "Device counts by connection, in the order the page draws them."
  @type connection_counts() :: %{
          online: non_neg_integer(),
          recent: non_neg_integer(),
          week: non_neg_integer(),
          stale: non_neg_integer(),
          never: non_neg_integer()
        }

  @typedoc "Device counts by health, in the order the page draws them."
  @type health_counts() :: %{
          healthy: non_neg_integer(),
          warning: non_neg_integer(),
          unhealthy: non_neg_integer(),
          unknown: non_neg_integer()
        }

  @typedoc """
  The devices on one firmware version: how many, their health, and how many
  aren't online. `version` is nil for devices that haven't reported one.
  """
  @type version_counts() :: %{
          version: String.t() | nil,
          count: pos_integer(),
          health: health_counts(),
          offline: non_neg_integer()
        }

  @typedoc """
  A product's fleet counted three ways, from `composition/2`.

  `versions` is every reported version, largest first and the newest of
  equal-sized ones first. `newest_version` is the highest version any device
  reports, by semantic version order.
  """
  @type composition() :: %{
          total: non_neg_integer(),
          connection: connection_counts(),
          health: health_counts(),
          versions: [version_counts()],
          newest_version: String.t() | nil
        }

  @typedoc """
  One row of the firmware breakdown, from `versions/1`: a reported version
  (`kind: :version`), the devices with no version (`kind: :unknown`), or the
  smaller versions folded together (`kind: :others`, with how many in
  `folded`).
  """
  @type version_row() :: %{
          kind: :version | :unknown | :others,
          version: String.t() | nil,
          folded: non_neg_integer(),
          count: pos_integer(),
          health: health_counts(),
          offline: non_neg_integer()
        }

  @typedoc """
  What the Insights page's "Stands out" card says, from `stands_out/1`:

    * `:version` - `row` has at least twice the fleet's share of devices
      that aren't healthy;
    * `:even` - no version does, and `rows` gives each version's share for
      comparison;
    * `:all_healthy` - every device is healthy;
    * `:single` - every device is on one version, `row`, so there is nothing
      to compare.

  `fleet_rate` is the fleet's share of devices that aren't healthy, and
  `not_healthy` how many that is.
  """
  @type stands_out() ::
          %{kind: :version, row: version_row(), rate: float(), fleet_rate: float(), not_healthy: non_neg_integer()}
          | %{kind: :even, rows: [version_row()], fleet_rate: float(), not_healthy: non_neg_integer()}
          | %{kind: :all_healthy, total: pos_integer(), offline: non_neg_integer()}
          | %{kind: :single, row: version_row(), fleet_rate: float(), not_healthy: non_neg_integer()}

  # Versions shown by name; past this they're folded into one "others" row,
  # so the composition bar and the table stay readable at a glance.
  @named_versions 4

  # A version stands out when the share of its devices that aren't healthy is
  # at least this many times the fleet's...
  @stands_out_ratio 2

  # ...and it has at least this many devices, so one bad device on a version
  # of three doesn't read as a finding.
  @stands_out_min_devices 10

  @no_connection %{online: 0, recent: 0, week: 0, stale: 0, never: 0}
  @no_health %{healthy: 0, warning: 0, unhealthy: 0, unknown: 0}

  @doc """
  Counts `product`'s devices by connection, health and firmware version, as
  of `now`.

  Soft-deleted devices are left out, so each grouping adds up to the
  product's fleet size.
  """
  @spec composition(Product.t(), DateTime.t()) :: composition()
  def composition(%Product{} = product, now \\ DateTime.utc_now()) do
    rows = composition_rows(product, now)

    by_version =
      rows
      |> Enum.group_by(& &1.version)
      |> Enum.map(fn {version, version_rows} -> version_counts(version, version_rows) end)
      |> Enum.sort_by(&{&1.count, &1.sort_key}, :desc)

    %{
      total: Enum.sum_by(rows, & &1.count),
      connection: Enum.reduce(rows, @no_connection, &Map.update!(&2, &1.connection, fn n -> n + &1.count end)),
      health: Enum.reduce(rows, @no_health, &Map.update!(&2, &1.health, fn n -> n + &1.count end)),
      versions: Enum.map(by_version, &Map.delete(&1, :sort_key)),
      newest_version: newest_version(by_version)
    }
  end

  @doc """
  The devices list filters for each connection group `composition/2` counts.
  Each lists exactly the devices its group counts, so a count can link to
  them.
  """
  @spec connection_filters() :: %{atom() => keyword()}
  def connection_filters() do
    %{
      online: [connection: "connected"],
      recent: [
        advanced_query:
          ~s{connection != "connected" and connection != "not_seen" and (connection != "disconnected" or last_seen > "7 days ago")}
      ],
      week: [advanced_query: ~s(last_seen < "7 days ago" and last_seen > "14 days ago")],
      stale: [connection: "not_seen_in_fourteen_days"],
      never: [advanced_query: ~s(connection = "not_seen")]
    }
  end

  # One row per firmware version, health status and connection group. Each
  # connection group is exactly what its filter in `connection_filters/0`
  # lists: never connected is a device still `registered`, and `last_seen`
  # only matches disconnected devices, so one still connecting, or with no
  # connection row at all, falls to recently seen.
  defp composition_rows(product, now) do
    seven_days_ago = DateTime.add(now, -7, :day)
    fourteen_days_ago = DateTime.add(now, -14, :day)

    Device
    |> where(product_id: ^product.id)
    |> Repo.exclude_deleted()
    |> join(:left, [d], lh in assoc(d, :latest_health))
    |> join(:left, [d], lc in assoc(d, :latest_connection))
    |> group_by([], [selected_as(:version), selected_as(:health), selected_as(:connection)])
    |> select([d, lh, lc], %{
      version: selected_as(fragment("? ->> 'version'", d.firmware_metadata), :version),
      health: selected_as(fragment("COALESCE(?, 'unknown')", lh.status), :health),
      connection:
        selected_as(
          fragment(
            """
            CASE
              WHEN ? = 'connected' THEN 'online'
              WHEN ? = 'registered' THEN 'never'
              WHEN ? = 'disconnected' AND ? < ? THEN 'stale'
              WHEN ? = 'disconnected' AND ? < ? THEN 'week'
              ELSE 'recent'
            END
            """,
            lc.status,
            d.status,
            lc.status,
            lc.last_seen_at,
            ^fourteen_days_ago,
            lc.status,
            lc.last_seen_at,
            ^seven_days_ago
          ),
          :connection
        ),
      sort_key: fragment(~s|MAX(semver_sort_key(? ->> 'version') COLLATE "C")|, d.firmware_metadata),
      count: count(d.id)
    })
    |> Repo.all()
    |> Enum.map(fn row ->
      %{row | health: String.to_existing_atom(row.health), connection: String.to_existing_atom(row.connection)}
    end)
  end

  defp version_counts(version, rows) do
    %{
      version: version,
      sort_key: rows |> Enum.map(& &1.sort_key) |> Enum.max(),
      count: Enum.sum_by(rows, & &1.count),
      health: Enum.reduce(rows, @no_health, &Map.update!(&2, &1.health, fn n -> n + &1.count end)),
      offline: rows |> Enum.reject(&(&1.connection == :online)) |> Enum.sum_by(& &1.count)
    }
  end

  defp newest_version(by_version) do
    by_version
    |> Enum.reject(&is_nil(&1.version))
    |> Enum.max_by(& &1.sort_key, fn -> nil end)
    |> case do
      nil -> nil
      %{version: version} -> version
    end
  end

  @doc """
  The rows of the firmware breakdown: the largest #{@named_versions} versions
  by name, in the order `composition/2` gives them, then the rest folded into
  one row. A single version left over is shown by name rather than folded on
  its own.
  """
  @spec versions(composition()) :: [version_row()]
  def versions(%{versions: versions}) do
    rows = Enum.map(versions, &version_row/1)

    case Enum.split(rows, @named_versions) do
      {named, []} -> named
      {named, [only]} -> named ++ [only]
      {named, rest} -> named ++ [fold(rest)]
    end
  end

  defp version_row(%{version: nil} = counts), do: Map.merge(counts, %{kind: :unknown, folded: 0})
  defp version_row(counts), do: Map.merge(counts, %{kind: :version, folded: 0})

  defp fold(rows) do
    %{
      kind: :others,
      version: nil,
      folded: length(rows),
      count: Enum.sum_by(rows, & &1.count),
      health: Map.new(@no_health, fn {status, _} -> {status, Enum.sum_by(rows, & &1.health[status])} end),
      offline: Enum.sum_by(rows, & &1.offline)
    }
  end

  @doc """
  How many of a set of counts aren't healthy: warning, unhealthy or unknown.
  """
  @spec not_healthy(health_counts()) :: non_neg_integer()
  def not_healthy(%{warning: warning, unhealthy: unhealthy, unknown: unknown})
      when is_integer(warning) and is_integer(unhealthy) and is_integer(unknown), do: warning + unhealthy + unknown

  @doc """
  What the "Stands out" card says about `composition`, or nil for a product
  with no devices. See `t:stands_out/0`.

  A version stands out when its share of devices that aren't healthy is at
  least #{@stands_out_ratio} times the fleet's and it has at least
  #{@stands_out_min_devices} devices. Of several that do, the one with the
  highest share is named. Only a reported version can stand out, not the
  devices with no version or the folded others.
  """
  @spec stands_out(composition()) :: stands_out() | nil
  def stands_out(%{total: 0}), do: nil

  def stands_out(%{total: total, health: health} = composition) do
    rows = versions(composition)
    not_healthy = not_healthy(health)
    fleet_rate = not_healthy / total

    cond do
      match?([_], rows) ->
        %{kind: :single, row: hd(rows), fleet_rate: fleet_rate, not_healthy: not_healthy}

      not_healthy == 0 ->
        offline = Enum.sum_by(rows, & &1.offline)
        %{kind: :all_healthy, total: total, offline: offline}

      row = standout_row(rows, fleet_rate) ->
        %{kind: :version, row: row, rate: rate(row), fleet_rate: fleet_rate, not_healthy: not_healthy}

      true ->
        %{kind: :even, rows: rows, fleet_rate: fleet_rate, not_healthy: not_healthy}
    end
  end

  defp standout_row(rows, fleet_rate) do
    rows
    |> Enum.filter(fn row ->
      row.kind == :version and row.count >= @stands_out_min_devices and rate(row) >= fleet_rate * @stands_out_ratio
    end)
    |> Enum.max_by(&{rate(&1), &1.count}, fn -> nil end)
  end

  @doc """
  The share of a row's devices that aren't healthy, from 0 to 1.
  """
  @spec rate(%{count: pos_integer(), health: health_counts()}) :: float()
  def rate(%{count: count, health: health}), do: not_healthy(health) / count
end
