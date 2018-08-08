defmodule NervesHubCore.Repo.Migrations.TenantToOrg do
  use Ecto.Migration

  def change do
    drop(unique_index(:products, [:tenant_id, :name], name: :products_tenant_id_name_index))
    drop(unique_index(:tenant_keys, [:tenant_id, :name], name: :tenant_keys_tenant_id_name_index))
    drop(unique_index(:tenant_keys, [:key]))

    rename(table(:tenants), to: table(:orgs))
    rename(table(:users), :tenant_id, to: :org_id)
    rename(table(:products), :tenant_id, to: :org_id)

    rename(table(:tenant_keys), :tenant_id, to: :org_id)
    rename(table(:tenant_keys), to: table(:org_keys))

    rename(table(:firmwares), :tenant_key_id, to: :org_key_id)

    rename(table(:devices), :tenant_id, to: :org_id)
    rename(table(:invites), :tenant_id, to: :org_id)

    create(unique_index(:products, [:org_id, :name], name: :products_org_id_name_index))
    create(unique_index(:org_keys, [:org_id, :name], name: :org_keys_org_id_name_index))
    create(unique_index(:org_keys, [:key]))
  end
end
