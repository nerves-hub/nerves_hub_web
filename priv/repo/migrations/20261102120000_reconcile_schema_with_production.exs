defmodule NervesHub.Repo.Migrations.ReconcileSchemaWithProduction do
  @moduledoc """
  Bring the migrations into line with the schema production actually has.

  Production picked up indexes by hand while queries were being tuned, and lost
  some `NOT NULL` constraints along the way, so a database built from migrations
  didn't match it.

  The `test_orchestrator_*` indexes are renamed by hand on production before this
  runs, and the hardly used `test_faster_*` ones are dropped by hand, so here they
  only need creating. If the renames haven't happened, production ends up with a
  copy of each index under its new name.

  Every step checks what is already there, because the two starting points need
  opposite things: production has the indexes and lacks the constraints, and a
  database built from migrations has the constraints and lacks the indexes. That
  also makes this safe to run again if it stops partway, which matters with no
  transaction around it.

  No column here holds a NULL in production, so setting `NOT NULL` won't fail
  there, and those tables are small enough for the check to be brief.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  @renamed_indexes [
    {"products_pkey_test", "products_live_id_index"},
    {"product_shared_secret_auth_test_index", "product_shared_secret_auth_active_key_index"}
  ]

  @index_definitions [
    "UNIQUE INDEX CONCURRENTLY IF NOT EXISTS products_live_id_index ON products (id) WHERE deleted_at IS NULL",
    "INDEX CONCURRENTLY IF NOT EXISTS product_shared_secret_auth_active_key_index ON product_shared_secret_auth (key) WHERE deactivated_at IS NULL",
    "INDEX CONCURRENTLY IF NOT EXISTS devices_deployment_updates_enabled_blocked_until_index ON devices (deployment_id, updates_enabled, COALESCE(updates_blocked_until, '1970-01-01 00:00:00'::timestamp without time zone))",
    "INDEX CONCURRENTLY IF NOT EXISTS devices_firmware_uuid_path_index ON devices ((firmware_metadata ->> 'uuid'))"
  ]

  # `devices_deployment_id_index` is covered by the deployment index above, and
  # production has already done without it.
  @dropped_indexes [
    "devices_deployment_id_index"
  ]

  @not_null_columns [
    {"ca_certificates", "org_id"},
    {"device_certificates", "device_id"},
    {"firmware_transfers", "org_id"},
    {"firmwares", "product_id"},
    {"jitp", "product_id"},
    {"org_metrics", "org_id"},
    {"products", "org_id"},
    {"user_certificates", "user_id"}
  ]

  def up() do
    for {from, to} <- @renamed_indexes do
      execute("ALTER INDEX IF EXISTS #{from} RENAME TO #{to}")
    end

    for definition <- @index_definitions do
      execute("CREATE #{definition}")
    end

    for index <- @dropped_indexes do
      execute("DROP INDEX CONCURRENTLY IF EXISTS #{index}")
    end

    for {table, column} <- @not_null_columns do
      execute("ALTER TABLE #{table} ALTER COLUMN #{column} SET NOT NULL")
    end
  end

  # Nothing to undo. Going back would mean different things on production and on
  # a database built from migrations, and `up` is safe to run again regardless.
  def down(), do: :ok
end
