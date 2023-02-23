defmodule NervesHub.Repo.Migrations.FixUniqueIndexDevicesIdentifier do
  use Ecto.Migration

  def change do
    rename(table(:devices), :org_id, to: :tenant_id)
    drop(unique_index(:devices, [:tenant_id, :identifier], name: :devices_tenant_id_identifier_index))
    rename(table(:devices), :tenant_id, to: :org_id)
    create(unique_index(:devices, [:org_id, :identifier], name: :devices_org_id_identifier_index))
  end
end
