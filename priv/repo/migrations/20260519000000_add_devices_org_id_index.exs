defmodule NervesHub.Repo.Migrations.AddDevicesOrgIdIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change() do
    create(index(:devices, [:org_id], concurrently: true))
  end
end
