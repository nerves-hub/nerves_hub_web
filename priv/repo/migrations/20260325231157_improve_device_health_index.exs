defmodule NervesHub.Repo.Migrations.ImproveDeviceHealthIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up() do
    drop(index(:device_health, [:device_id, :inserted_at], concurrently: true))
    create(index(:device_health, [:device_id, desc: :inserted_at], concurrently: true))
  end

  def down() do
    create(index(:device_health, [:device_id, :inserted_at], concurrently: true))
    drop(index(:device_health, [:status, :last_seen_at]))
  end
end
