defmodule NervesHub.Repo.Migrations.CreateHealthProfiles do
  use Ecto.Migration

  def up() do
    create table(:health_profiles) do
      add(:product_id, references(:products, on_delete: :delete_all), null: false)
      add(:platform, :string)

      timestamps()
    end

    # One profile per platform, and `nulls_distinct: false` makes the NULL
    # platform (the product default) unique per product too.
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
      add(:warning_threshold, :float, null: false)
      add(:warning_period_minutes, :integer, null: false)
      add(:alert_threshold, :float, null: false)
      add(:alert_period_minutes, :integer, null: false)

      timestamps()
    end

    create(unique_index(:health_profile_metrics, [:health_profile_id, :key]))

    # Every existing product gets a default profile carrying the thresholds
    # that were hardcoded in NervesHub.Devices.HealthStatus until now, averaged
    # over an hour (one idle-paced report). Values are duplicated here rather
    # than read from the module so the migration stays frozen.
    execute("""
    INSERT INTO health_profiles (product_id, platform, inserted_at, updated_at)
    SELECT id, NULL, now(), now()
    FROM products
    WHERE deleted_at IS NULL
    """)

    execute("""
    INSERT INTO health_profile_metrics
      (health_profile_id, key, built_in, featured, warning_threshold, warning_period_minutes,
       alert_threshold, alert_period_minutes, inserted_at, updated_at)
    SELECT hp.id, defaults.key, false, true, defaults.warning, 60, defaults.alert, 60, now(), now()
    FROM health_profiles hp
    CROSS JOIN (
      VALUES
        ('cpu_usage_percent', 80.0, 90.0),
        ('mem_used_percent', 70.0, 80.0),
        ('disk_used_percentage', 80.0, 90.0)
    ) AS defaults(key, warning, alert)
    WHERE hp.platform IS NULL
    """)
  end

  def down() do
    drop(table(:health_profile_metrics))
    drop(table(:health_profiles))
  end
end
