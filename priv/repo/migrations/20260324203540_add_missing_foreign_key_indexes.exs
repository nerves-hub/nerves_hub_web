defmodule NervesHub.Repo.Migrations.AddMissingForeignKeyIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:archives, [:org_key_id], concurrently: true)
    create index(:ca_certificates, [:org_id], concurrently: true)
    create index(:deployment_releases, [:created_by_id], concurrently: true)
    create index(:deployments, [:org_id], concurrently: true)
    create index(:device_certificates, [:org_id], concurrently: true)
    create index(:device_shared_secret_auths, [:device_id], concurrently: true)
    create index(:device_shared_secret_auths, [:product_shared_secret_auth_id], concurrently: true)
    create index(:devices, [:org_id], concurrently: true)
    create index(:firmware_deltas, [:target_id], concurrently: true)
    create index(:firmware_transfers, [:org_id], concurrently: true)
    create index(:firmwares, [:org_id], concurrently: true)
    create index(:firmwares, [:org_key_id], concurrently: true)
    create index(:inflight_deployment_checks, [:deployment_id], concurrently: true)
    create index(:inflight_deployment_checks, [:device_id], concurrently: true)
    create index(:inflight_updates, [:firmware_id], concurrently: true)
    create index(:invites, [:invited_by_id], concurrently: true)
    create index(:invites, [:org_id], concurrently: true)
    create index(:jitp, [:product_id], concurrently: true)
    create index(:org_keys, [:created_by_id], concurrently: true)
    create index(:org_users, [:user_id], concurrently: true)
    create index(:pinned_devices, [:device_id], concurrently: true)
    create index(:pinned_devices, [:user_id], concurrently: true)
    create index(:product_shared_secret_auth, [:product_id], concurrently: true)
    create index(:product_users, [:user_id], concurrently: true)
    create index(:scripts, [:created_by_id], concurrently: true)
    create index(:scripts, [:last_updated_by_id], concurrently: true)
    create index(:scripts, [:product_id], concurrently: true)
    create index(:user_tokens, [:user_id], concurrently: true)
  end
end
