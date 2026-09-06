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
  alias NervesHub.Devices.HealthStatus
  alias NervesHub.Products.HealthProfile
  alias NervesHub.Products.HealthProfileMetric
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

  Runs inside product creation (see `NervesHub.Products.create_product/1`);
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
    {:ok, Repo.delete!(profile)}
  end

  @doc """
  Adds a metric to a profile. `built_in` is decided here from the key, never
  taken from the caller: a key is a built-in exactly when it is registered in
  `built_in_metrics/0`.
  """
  @spec add_metric(HealthProfile.t(), map()) ::
          {:ok, HealthProfileMetric.t()} | {:error, Ecto.Changeset.t()}
  def add_metric(%HealthProfile{id: profile_id}, attrs) do
    built_in? = Map.has_key?(@built_in_metrics, String.trim(attrs["key"] || ""))

    attrs =
      attrs
      |> Map.put("health_profile_id", profile_id)
      |> Map.put("built_in", built_in?)

    # A built-in defines its own unhealthy direction (a disconnect count only
    # goes bad high), so the operator is not the caller's to choose.
    attrs = if built_in?, do: Map.put(attrs, "operator", "gte"), else: attrs

    %HealthProfileMetric{}
    |> HealthProfileMetric.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a metric's thresholds and periods. The key (and with it the
  built-in flag) is fixed once added; remove and re-add to change it.
  """
  @spec update_metric(HealthProfileMetric.t(), map()) ::
          {:ok, HealthProfileMetric.t()} | {:error, Ecto.Changeset.t()}
  def update_metric(%HealthProfileMetric{} = metric, attrs) do
    fixed =
      if metric.built_in,
        do: ["key", "built_in", "health_profile_id", "operator"],
        else: ["key", "built_in", "health_profile_id"]

    metric
    |> HealthProfileMetric.changeset(Map.drop(attrs, fixed))
    |> Repo.update()
  end

  @spec get_metric!(HealthProfile.t(), pos_integer()) :: HealthProfileMetric.t()
  def get_metric!(%HealthProfile{id: profile_id}, id) do
    HealthProfileMetric
    |> where(health_profile_id: ^profile_id, id: ^id)
    |> Repo.one!()
  end

  @spec delete_metric(HealthProfileMetric.t()) :: :ok
  def delete_metric(%HealthProfileMetric{} = metric) do
    Repo.delete!(metric)
    :ok
  end
end
