defmodule NervesHub.Repo.Migrations.CreateHealthProfiles do
  use Ecto.Migration

  import Ecto.Query

  # The thresholds that were hardcoded in NervesHub.Devices.HealthStatus until
  # now, measured over an hour (one idle-paced report). Duplicated here rather
  # than read from the module so the migration stays frozen.
  @default_metrics [
    {"cpu_usage_percent", 80.0, 90.0},
    {"disk_used_percentage", 80.0, 90.0},
    {"mem_used_percent", 70.0, 80.0}
  ]
  @default_period_seconds 3600

  def up() do
    create table(:health_profiles) do
      add(:product_id, references(:products, on_delete: :delete_all), null: false)
      add(:platform, :string)

      timestamps()
    end

    # One profile per platform, and `nulls_distinct: false` makes the NULL
    # platform (the product default) unique per product too. Requires
    # PostgreSQL 15+ (the README recommends 18).
    create(
      unique_index(:health_profiles, [:product_id, :platform],
        name: :health_profiles_product_id_platform_index,
        nulls_distinct: false
      )
    )

    create table(:health_profile_metrics) do
      add(:health_profile_id, references(:health_profiles, on_delete: :delete_all), null: false)
      add(:key, :string, null: false)
      add(:built_in, :boolean, null: false, default: false)
      add(:featured, :boolean, null: false, default: false)
      # Which direction is unhealthy: "gte" engages at or above the
      # thresholds, "lte" at or below (frame rates go bad low).
      add(:operator, :string, null: false, default: "gte")
      add(:warning_threshold, :float, null: false)
      add(:warning_period_seconds, :integer, null: false)
      add(:alert_threshold, :float, null: false)
      add(:alert_period_seconds, :integer, null: false)

      timestamps()
    end

    create(unique_index(:health_profile_metrics, [:health_profile_id, :key]))

    flush()

    # Every existing product gets a default profile carrying the previously
    # hardcoded thresholds, with each metric featured. Note the deliberate
    # display change this brings to existing device-details pages: the old
    # fixed tiles were CPU / Memory / Load, the featured defaults render as
    # CPU / Disk / Memory — Load has no defensible universal thresholds, so
    # it is not in the default profile, and disk (which always had one) is.
    # Feature a load metric on the profile to bring that tile back.
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    product_ids = repo().all(from(p in "products", where: is_nil(p.deleted_at), select: p.id))

    profiles =
      Enum.map(product_ids, fn product_id ->
        %{product_id: product_id, platform: nil, inserted_at: now, updated_at: now}
      end)

    if profiles != [] do
      {_count, profile_rows} = repo().insert_all("health_profiles", profiles, returning: [:id])

      metrics =
        for %{id: profile_id} <- profile_rows, {key, warning, alert} <- @default_metrics do
          %{
            health_profile_id: profile_id,
            key: key,
            built_in: false,
            featured: true,
            operator: "gte",
            warning_threshold: warning,
            warning_period_seconds: @default_period_seconds,
            alert_threshold: alert,
            alert_period_seconds: @default_period_seconds,
            inserted_at: now,
            updated_at: now
          }
        end

      repo().insert_all("health_profile_metrics", metrics)
    end
  end

  def down() do
    drop(table(:health_profile_metrics))
    drop(table(:health_profiles))
  end
end
