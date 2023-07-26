defmodule NervesHub.Repo.Migrations.CreateUniqueIndexOnDevices do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create index(:devices, [:identifier], unique: true, concurrently: true)
    drop index(:devices, [:org_id, :identifier])
  end
end
