defmodule NervesHub.Repo.Migrations.DropDeviceMetrics do
  use Ecto.Migration

  def up() do
    # Dropping this table also drops its foreign key into `devices`, and
    # Postgres takes an ACCESS EXCLUSIVE lock on the *referenced* table to do
    # that. `devices` is the busiest table in the system, so a drop that has to
    # queue behind a long-running read would then have every other query queue
    # behind the drop.
    #
    # A short lock timeout makes that a failed migration instead of a stall.
    # Migrations run on boot, so the answer to hitting it is to deploy again at
    # a quieter moment; the work itself is unlinking files and takes no time
    # once the lock is held.
    execute("SET lock_timeout = '5s'")

    drop(table(:device_metrics))
  end

  def down() do
    create table(:device_metrics) do
      add(:device_id, references(:devices), null: false)
      add(:key, :string)
      add(:value, :float)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:device_metrics, [:device_id, :inserted_at]))
    create(index(:device_metrics, [:key, :inserted_at]))
    create(index(:device_metrics, [:inserted_at]))
  end
end
