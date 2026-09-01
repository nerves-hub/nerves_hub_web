defmodule NervesHub.Products.HealthProfileMetric do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Products.HealthProfile

  @type t :: %__MODULE__{}

  @required [
    :health_profile_id,
    :key,
    :warning_threshold,
    :warning_period_seconds,
    :alert_threshold,
    :alert_period_seconds
  ]

  # A measurement period is a window over recent samples: at least a minute
  # (the evaluation granularity), at most 24 hours — idle devices report once
  # an hour, so day-scale windows are what gives their medians more than a
  # sample or two to work with. Stored in seconds so the granularity can
  # change without a schema migration.
  @max_period_seconds 24 * 3600

  schema "health_profile_metrics" do
    belongs_to(:health_profile, HealthProfile)

    field(:key, :string)

    # A built-in metric is not read from `device_metrics`: its key names a
    # platform-provided signal (see `HealthProfiles.built_in_metrics/0`) that is
    # evaluated with its own query, e.g. "disconnects" counts connectivity
    # events. The flag is explicit so a device reporting a metric that happens
    # to share a built-in's name can never change what an existing row means.
    field(:built_in, :boolean, default: false)

    # Featured metrics are the ones surfaced at the top of the device details
    # page; the rest still count toward health but only show on the health tab.
    field(:featured, :boolean, default: false)

    field(:warning_threshold, :float)
    field(:warning_period_seconds, :integer)
    field(:alert_threshold, :float)
    field(:alert_period_seconds, :integer)

    timestamps()
  end

  def max_period_seconds(), do: @max_period_seconds

  def changeset(struct, params) do
    struct
    |> cast(params, @required ++ [:built_in, :featured])
    |> validate_required(@required)
    |> update_change(:key, &String.trim/1)
    |> validate_length(:key, min: 1, max: 255)
    |> validate_number(:warning_period_seconds,
      greater_than_or_equal_to: 60,
      less_than_or_equal_to: @max_period_seconds,
      message: "must be between 1 minute and 24 hours"
    )
    |> validate_number(:alert_period_seconds,
      greater_than_or_equal_to: 60,
      less_than_or_equal_to: @max_period_seconds,
      message: "must be between 1 minute and 24 hours"
    )
    |> validate_alert_not_below_warning()
    |> foreign_key_constraint(:health_profile_id)
    |> unique_constraint(:key,
      name: :health_profile_metrics_health_profile_id_key_index,
      message: "is already in this profile"
    )
  end

  # Levels engage at value >= threshold, so an alert threshold below the
  # warning threshold would make the warning level unreachable.
  defp validate_alert_not_below_warning(changeset) do
    warning = get_field(changeset, :warning_threshold)
    alert = get_field(changeset, :alert_threshold)

    if is_number(warning) and is_number(alert) and alert < warning do
      add_error(changeset, :alert_threshold, "must be greater than or equal to the warning threshold")
    else
      changeset
    end
  end
end
