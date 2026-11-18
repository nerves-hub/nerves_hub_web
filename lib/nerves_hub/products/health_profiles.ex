defmodule NervesHub.Products.HealthProfiles do
  @moduledoc """
  Health profiles: per-product (optionally per-platform) thresholds that decide
  whether a device is healthy.

  Every product owns a default profile (`platform: nil`), created with the
  product and backfilled for existing products by a data migration. A platform
  profile overrides the default for devices whose firmware reports that
  platform, so hardware differences can carry different thresholds.

  A profile holds any number of metrics, each with a warning and an alert
  level: a level engages when the metric's median over that level's
  measurement period (a minute to 24 hours) reaches the level's threshold.
  Most metrics read the values devices report; a metric flagged `built_in`
  is a virtual one evaluated with its own query (e.g. "disconnects" counts
  connectivity events). Evaluation happens as reports arrive, in
  `NervesHub.Devices.HealthEvaluation`.

  A metric can also be flagged `featured`, which is about display rather than
  status: featured metrics are the ones surfaced at the top of the device
  details page.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias NervesHub.Accounts.User
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceHealth
  alias NervesHub.Devices.HealthEvaluation
  alias NervesHub.Devices.HealthStatus
  alias NervesHub.Devices.Metrics
  alias NervesHub.Devices.Visibility
  alias NervesHub.Products.HealthProfile
  alias NervesHub.Products.HealthProfileMetric
  alias NervesHub.Products.HealthProfiles.Cache
  alias NervesHub.Products.Product
  alias NervesHub.Repo

  @default_period_seconds 3600

  @built_in_metrics %{
    "disconnects" => %{
      label: "Disconnects",
      description: "How many times the device disconnected during the measurement period."
    }
  }

  @doc """
  The virtual metrics a profile can include besides device-reported ones, as
  `%{key => %{label: ..., description: ...}}`.
  """
  @spec built_in_metrics() :: %{optional(String.t()) => %{label: String.t(), description: String.t()}}
  def built_in_metrics(), do: @built_in_metrics

  @doc """
  The metrics a brand-new default profile starts with.

  Thresholds come from `NervesHub.Devices.HealthStatus.default_thresholds/0`
  — the previously hardcoded trio plus a 15-minute load average at 8/10 —
  measured over an hour (one idle-paced report) so behaviour stays close to
  the old latest-value check. Featuring these defaults keeps the old
  CPU / Memory / Load device-details tiles and adds a Disk one.
  """
  @spec default_metric_attrs() :: [map()]
  def default_metric_attrs() do
    HealthStatus.default_thresholds()
    |> Enum.map(fn {key, %{warning: warning, unhealthy: alert}} ->
      %{
        key: key,
        built_in: false,
        featured: true,
        operator: :gte,
        warning_threshold: warning / 1,
        warning_period_seconds: @default_period_seconds,
        alert_threshold: alert / 1,
        alert_period_seconds: @default_period_seconds
      }
    end)
    |> Enum.sort_by(& &1.key)
  end

  @doc """
  All profiles for a product, default first, then platforms alphabetically.
  """
  @spec all_for_product(Product.t()) :: [HealthProfile.t()]
  def all_for_product(%Product{id: product_id}) do
    HealthProfile
    |> where(product_id: ^product_id)
    |> order_by([p], asc_nulls_first: p.platform)
    |> preload(:metrics)
    |> Repo.all()
  end

  @doc """
  How many health profiles a product has, default included.
  """
  @spec count_for_product(Product.t()) :: non_neg_integer()
  def count_for_product(%Product{id: product_id}) do
    HealthProfile
    |> where(product_id: ^product_id)
    |> select([p], count(p.id))
    |> Repo.one!()
  end

  @doc """
  How many of the product's devices each of its profiles applies to, keyed
  by the profile's platform (`nil` for the default profile).

  A device takes its platform's profile if there is one, and the default
  otherwise. Counts only the devices `user` can see.
  """
  @spec device_counts(Product.t(), User.t(), [HealthProfile.t()]) :: %{optional(String.t() | nil) => non_neg_integer()}
  def device_counts(%Product{} = product, %User{} = user, profiles) do
    platforms = profiles |> Enum.map(& &1.platform) |> Enum.reject(&is_nil/1)

    counts =
      product
      |> devices_query(user)
      |> group_by([d], fragment("?->>'platform'", d.firmware_metadata))
      |> select([d], {fragment("?->>'platform'", d.firmware_metadata), count(d.id)})
      |> Repo.all()

    Enum.reduce(counts, Map.new(profiles, &{&1.platform, 0}), fn {platform, count}, acc ->
      profile_platform = if platform in platforms, do: platform
      Map.update(acc, profile_platform, count, &(&1 + count))
    end)
  end

  @doc """
  How many of the devices `profile` applies to are healthy, warning,
  unhealthy or unknown right now, as their health was last judged.

  `profiles` is every profile of the product, which decides the devices the
  default profile is left with. Counts only the devices `user` can see.
  """
  @spec health_counts(Product.t(), User.t(), HealthProfile.t(), [HealthProfile.t()]) ::
          %{HealthEvaluation.status() => non_neg_integer()}
  def health_counts(%Product{} = product, %User{} = user, %HealthProfile{} = profile, profiles) do
    counts =
      product
      |> profile_devices_query(user, profile, profiles)
      |> join(:left, [d], h in DeviceHealth, on: h.device_id == d.id)
      |> group_by([d, h], h.status)
      |> select([d, h], {h.status, count(d.id)})
      |> Repo.all()

    Enum.reduce(counts, %{healthy: 0, warning: 0, unhealthy: 0, unknown: 0}, fn {status, count}, acc ->
      Map.update!(acc, status || :unknown, &(&1 + count))
    end)
  end

  @doc """
  How many of the devices `profile` applies to `metrics` would judge
  healthy, warning, unhealthy or unknown right now.

  For showing what a change to a profile does before it's saved: pass the
  edited metrics, and the saved ones to compare. Readings still in the write
  buffer aren't counted, so this can lag the devices' own health by a few
  seconds; comparing two previews cancels that out. Counts only the devices
  `user` can see. Needs analytics; `nil` without it.
  """
  @spec preview_counts(Product.t(), User.t(), HealthProfile.t(), [HealthProfile.t()], [HealthProfileMetric.t()]) ::
          %{HealthEvaluation.status() => non_neg_integer()} | nil
  def preview_counts(%Product{} = product, %User{} = user, %HealthProfile{} = profile, profiles, metrics) do
    if Application.get_env(:nerves_hub, :analytics_enabled, false) do
      device_ids = product |> profile_devices_query(user, profile, profiles) |> select([d], d.id) |> Repo.all()
      now_minute = HealthEvaluation.minute(DateTime.utc_now())

      {built_in, regular} = Enum.split_with(metrics, & &1.built_in)
      reported = Metrics.fleet_health_levels(product.id, regular, now_minute)
      disconnects = Enum.find(built_in, &(&1.key == "disconnects"))

      disconnected =
        if disconnects, do: Connections.fleet_disconnection_levels(product.org_id, product.id, disconnects), else: %{}

      Enum.reduce(device_ids, %{healthy: 0, warning: 0, unhealthy: 0, unknown: 0}, fn device_id, acc ->
        # The disconnects built-in judges every device, healthy when it
        # hasn't disconnected enough, as `HealthEvaluation` does.
        level =
          case {Map.get(reported, device_id), Map.get(disconnected, device_id, if(disconnects, do: 0))} do
            {nil, nil} -> nil
            {a, b} -> max(a || 0, b || 0)
          end

        Map.update!(acc, status_for_level(level), &(&1 + 1))
      end)
    end
  end

  defp status_for_level(nil), do: :unknown
  defp status_for_level(0), do: :healthy
  defp status_for_level(1), do: :warning
  defp status_for_level(2), do: :unhealthy

  # The product's devices, as `user` can see them.
  defp devices_query(%Product{id: product_id}, user) do
    Device
    |> where([d], d.product_id == ^product_id and is_nil(d.deleted_at))
    |> Visibility.where_visible(user)
  end

  # The devices `profile` applies to: those on its platform, or for the
  # default profile, those on a platform no other profile covers.
  defp profile_devices_query(product, user, %HealthProfile{platform: nil}, profiles) do
    others = profiles |> Enum.map(& &1.platform) |> Enum.reject(&is_nil/1)

    where(
      devices_query(product, user),
      [d],
      is_nil(fragment("?->>'platform'", d.firmware_metadata)) or
        fragment("?->>'platform'", d.firmware_metadata) not in ^others
    )
  end

  defp profile_devices_query(product, user, %HealthProfile{platform: platform}, _profiles) do
    where(devices_query(product, user), [d], fragment("?->>'platform'", d.firmware_metadata) == ^platform)
  end

  @spec get_profile!(Product.t(), pos_integer()) :: HealthProfile.t()
  def get_profile!(%Product{id: product_id}, id) do
    HealthProfile
    |> where(product_id: ^product_id, id: ^id)
    |> preload(:metrics)
    |> Repo.one!()
  end

  @doc """
  The profile that applies to a device: the profile of the platform its
  firmware reports, when one exists, the product default otherwise. Takes
  anything shaped like a device — a `Device`, a `DeviceLink.DeviceInfo` —
  or a product id and a platform.

  `nil` only for products that predate health profiles without the backfill
  having run, or when the default profile has been removed directly in the
  database; callers fall back to the legacy hardcoded thresholds.
  """
  @spec resolve(%{:product_id => pos_integer(), optional(atom()) => any()}) :: HealthProfile.t() | nil
  def resolve(%{product_id: product_id} = device), do: resolve(product_id, platform(device))

  @spec resolve(pos_integer(), String.t() | nil) :: HealthProfile.t() | nil
  def resolve(product_id, platform) do
    Cache.fetch({product_id, platform}, fn -> load(product_id, platform) end)
  end

  defp load(product_id, platform) do
    HealthProfile
    |> where(product_id: ^product_id)
    |> platform_or_default(platform)
    # A platform match (platform not null) sorts before the default.
    |> order_by([p], asc: is_nil(p.platform))
    |> limit(1)
    |> preload(:metrics)
    |> Repo.one()
  end

  defp platform_or_default(query, nil), do: where(query, [p], is_nil(p.platform))
  defp platform_or_default(query, platform), do: where(query, [p], is_nil(p.platform) or p.platform == ^platform)

  defp platform(%{firmware_metadata: %{platform: platform}}), do: platform
  defp platform(%{firmware_metadata: %{"platform" => platform}}), do: platform
  defp platform(_device), do: nil

  @doc """
  Keys of the featured metrics in the device's profile — the metrics
  surfaced at the top of the device details page. Built-ins are left out:
  they have no reported value to put in a tile. `nil` when the product has
  no profile, so the caller can fall back to the legacy fixed tiles.
  """
  @spec featured_keys(%{:product_id => pos_integer(), optional(atom()) => any()}) :: [String.t()] | nil
  def featured_keys(device) do
    case resolve(device) do
      nil ->
        nil

      profile ->
        for metric <- profile.metrics, metric.featured, !metric.built_in, do: metric.key
    end
  end

  # Enough history to have seen a full week cycle (weekday vs weekend
  # behavior), and enough samples for the quartiles to mean something.
  @suggestion_minimum_days 7
  @suggestion_minimum_samples 100

  @doc """
  Threshold suggestions derived from a metric's observed fleet history (the
  per-key stats of `NervesHub.Devices.Metrics.observed_stats/1`), or `nil`
  when the history cannot support one.

  Uses Tukey's fences — warning at `Q3 + 1.5 * IQR`, alert at `Q3 + 3 * IQR`
  (mirrored below `Q1` for the `lte` direction) — the boxplot outlier rule.
  Not standard deviations: those assume roughly bell-shaped data and are
  themselves dragged by the freak readings device metrics produce, the same
  reason evaluation judges a median and not a mean. Quartiles ignore the
  extreme tails entirely, so one glitch in the history cannot move the
  suggestion, and the fences scale with the metric's own normal spread.

  `nil` when the history spans less than #{@suggestion_minimum_days} days
  (a threshold suggested before a full week cycle has been seen would read
  weekend behavior as an anomaly), holds fewer than
  #{@suggestion_minimum_samples} samples, or has zero spread between the
  quartiles (the fences would sit on the median itself, where half of all
  normal samples already "breach").

  Values are rounded to three significant digits: they are suggestions to
  adjust, not measurements.
  """
  @spec suggested_thresholds(map() | nil) ::
          %{gte: %{warning: float(), alert: float()}, lte: %{warning: float(), alert: float()}} | nil
  def suggested_thresholds(%{q1: q1, q3: q3, samples: samples, oldest: oldest}) do
    iqr = q3 - q1
    week_ago = DateTime.add(DateTime.utc_now(), -@suggestion_minimum_days, :day)

    if samples >= @suggestion_minimum_samples and DateTime.before?(oldest, week_ago) and iqr > 0 do
      %{
        gte: %{warning: round_sig(q3 + 1.5 * iqr), alert: round_sig(q3 + 3 * iqr)},
        lte: %{warning: round_sig(q1 - 1.5 * iqr), alert: round_sig(q1 - 3 * iqr)}
      }
    end
  end

  def suggested_thresholds(_no_stats), do: nil

  @sig_digits 3

  defp round_sig(value) when value == 0, do: 0.0

  defp round_sig(value) do
    magnitude = value |> abs() |> :math.log10() |> :math.floor() |> trunc()
    factor = :math.pow(10, @sig_digits - 1 - magnitude)
    round(value * factor) / factor
  end

  @doc """
  Creates the product's default profile, seeded with `default_metric_attrs/0`.

  Runs inside product creation (see `NervesHub.Products.create_product/2`);
  also the backstop for older products that somehow missed the backfill.
  """
  @spec create_default_profile(pos_integer()) :: {:ok, HealthProfile.t()} | {:error, Ecto.Changeset.t()}
  def create_default_profile(product_id) do
    create_profile_with_metrics(product_id, nil, default_metric_attrs())
  end

  @doc """
  Creates a platform-scoped profile, seeded from the product's default profile
  so it starts as a copy to adjust rather than a blank slate.
  """
  @spec create_platform_profile(Product.t(), String.t()) ::
          {:ok, HealthProfile.t()} | {:error, Ecto.Changeset.t()}
  def create_platform_profile(%Product{id: product_id}, platform) do
    metrics =
      case resolve(product_id, nil) do
        nil ->
          default_metric_attrs()

        default ->
          Enum.map(
            default.metrics,
            &Map.take(&1, [
              :key,
              :built_in,
              :featured,
              :operator,
              :warning_threshold,
              :warning_period_seconds,
              :alert_threshold,
              :alert_period_seconds
            ])
          )
      end

    create_profile_with_metrics(product_id, platform, metrics)
  end

  defp create_profile_with_metrics(product_id, platform, metric_attrs) do
    Multi.new()
    |> Multi.insert(:profile, HealthProfile.changeset(%HealthProfile{}, %{product_id: product_id, platform: platform}))
    |> Multi.merge(fn %{profile: profile} ->
      metric_attrs
      |> Enum.with_index()
      |> Enum.reduce(Multi.new(), fn {attrs, index}, multi ->
        changeset =
          HealthProfileMetric.changeset(%HealthProfileMetric{}, Map.put(attrs, :health_profile_id, profile.id))

        Multi.insert(multi, {:metric, index}, changeset)
      end)
    end)
    |> Repo.transact()
    |> case do
      {:ok, %{profile: profile}} ->
        :ok = Cache.invalidate(product_id)
        {:ok, Repo.preload(profile, :metrics)}

      {:error, _step, changeset, _} ->
        {:error, changeset}
    end
  end

  @doc """
  Deletes a platform profile; the default profile cannot be deleted, since
  every product is expected to keep one.
  """
  @spec delete_profile(HealthProfile.t()) :: {:ok, HealthProfile.t()} | {:error, :cannot_delete_default}
  def delete_profile(%HealthProfile{platform: nil}), do: {:error, :cannot_delete_default}

  def delete_profile(%HealthProfile{} = profile) do
    deleted = Repo.delete!(profile)
    :ok = Cache.invalidate(profile.product_id)

    {:ok, deleted}
  end

  @doc """
  Adds a metric to a profile. `built_in` is decided here from the key, never
  taken from the caller: a key is a built-in exactly when it is registered in
  `built_in_metrics/0`.
  """
  @spec add_metric(HealthProfile.t(), map()) ::
          {:ok, HealthProfileMetric.t()} | {:error, Ecto.Changeset.t()}
  def add_metric(%HealthProfile{product_id: product_id} = profile, attrs) do
    profile
    |> new_metric_changeset(attrs)
    |> Repo.insert()
    |> tap_ok(product_id)
  end

  @doc """
  Updates a metric's thresholds and periods. The key (and with it the
  built-in flag) is fixed once added; remove and re-add to change it.
  """
  @spec update_metric(HealthProfileMetric.t(), map()) ::
          {:ok, HealthProfileMetric.t()} | {:error, Ecto.Changeset.t()}
  def update_metric(%HealthProfileMetric{} = metric, attrs) do
    metric
    |> edit_metric_changeset(attrs)
    |> Repo.update()
    |> tap_ok(product_id_of(metric))
  end

  @doc """
  Saves a profile's metrics as `metrics` lists them, in one transaction:
  each entry with an `"id"` of one of the profile's metrics updates it, each
  without one adds a metric, and the profile's metrics left out are removed.

  The rules of `add_metric/2` and `update_metric/2` apply to each. The
  profile's metrics are read as they are now, not from `profile`, so a save
  made from a page loaded before someone else changed the profile still
  leaves it as `metrics` lists them: an `"id"` that's no longer the
  profile's adds the metric again. Returns the saved profile, or the
  position in `metrics` of the first entry that didn't validate, with its
  changeset.
  """
  @spec save_metrics(HealthProfile.t(), [map()]) ::
          {:ok, HealthProfile.t()} | {:error, non_neg_integer(), Ecto.Changeset.t()}
  def save_metrics(%HealthProfile{} = profile, metrics) do
    existing =
      HealthProfileMetric
      |> where(health_profile_id: ^profile.id)
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    kept = for attrs <- metrics, id = parse_id(attrs["id"]), Map.has_key?(existing, id), do: id

    # Removals go first, so a metric removed and added back in one save
    # doesn't trip over its own key. Deleting by query also removes a
    # metric added elsewhere since `existing` was read.
    removed = where(HealthProfileMetric, [m], m.health_profile_id == ^profile.id and m.id not in ^kept)

    metrics
    |> Enum.with_index()
    |> Enum.reduce(Multi.delete_all(Multi.new(), :remove, removed), fn {attrs, index}, multi ->
      case Map.fetch(existing, parse_id(attrs["id"])) do
        {:ok, metric} ->
          # A metric removed elsewhere after `existing` was read fails its
          # row rather than raising.
          changeset = edit_metric_changeset(metric, attrs)

          Multi.update(multi, {:metric, index}, changeset,
            stale_error_field: :key,
            stale_error_message: "was removed by someone else while you were editing"
          )

        :error ->
          Multi.insert(multi, {:metric, index}, new_metric_changeset(profile, attrs))
      end
    end)
    |> Repo.transact()
    |> case do
      {:ok, _changes} ->
        :ok = Cache.invalidate(profile.product_id)
        {:ok, get_profile!(%Product{id: profile.product_id}, profile.id)}

      {:error, {:metric, index}, changeset, _changes} ->
        {:error, index, changeset}
    end
  end

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> id
      _not_an_id -> nil
    end
  end

  defp parse_id(_none), do: nil

  # `built_in` is decided from the key, never taken from the caller: a key is
  # a built-in exactly when it's registered in `built_in_metrics/0`.
  defp new_metric_changeset(%HealthProfile{id: profile_id}, attrs) do
    built_in? = Map.has_key?(@built_in_metrics, String.trim(attrs["key"] || ""))

    attrs =
      attrs
      |> Map.delete("id")
      |> Map.put("health_profile_id", profile_id)
      |> Map.put("built_in", built_in?)

    # A built-in defines its own unhealthy direction (a disconnect count only
    # goes bad high), so the operator is not the caller's to choose.
    attrs = if built_in?, do: Map.put(attrs, "operator", "gte"), else: attrs

    HealthProfileMetric.changeset(%HealthProfileMetric{}, attrs)
  end

  defp edit_metric_changeset(%HealthProfileMetric{} = metric, attrs) do
    fixed =
      if metric.built_in,
        do: ["id", "key", "built_in", "health_profile_id", "operator"],
        else: ["id", "key", "built_in", "health_profile_id"]

    HealthProfileMetric.changeset(metric, Map.drop(attrs, fixed))
  end

  @spec delete_metric(HealthProfileMetric.t()) :: :ok
  def delete_metric(%HealthProfileMetric{} = metric) do
    product_id = product_id_of(metric)
    Repo.delete!(metric)

    Cache.invalidate(product_id)
  end

  # A metric knows its profile, not its product; the cache is keyed by
  # product. One query on an admin action, never on a report.
  defp product_id_of(%HealthProfileMetric{health_profile_id: profile_id}) do
    HealthProfile
    |> where(id: ^profile_id)
    |> select([p], p.product_id)
    |> Repo.one!()
  end

  # Drop the product's cached profiles when a write succeeded, and only then.
  defp tap_ok({:ok, _} = result, product_id) do
    :ok = Cache.invalidate(product_id)
    result
  end

  defp tap_ok({:error, _} = result, _product_id), do: result
end
