defmodule NervesHub.Repo.Migrations.AddUpdateModeIndexesToDevices do
  @moduledoc """
  `update_mode` counterparts to the `updates_enabled` indexes.

  The available-devices query is the orchestrator's hot path, and it now filters
  on `update_mode` rather than `updates_enabled`, so it needs its own index
  rather than inheriting one. The `updates_enabled` indexes stay until that
  column is dropped in the next release.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change() do
    create_if_not_exists(
      index(
        :devices,
        [
          :deployment_id,
          :update_mode,
          :firmware_validation_status,
          "COALESCE(updates_blocked_until, '1970-01-01 00:00:00'::timestamp)"
        ],
        where: "firmware_metadata IS NOT NULL",
        concurrently: true,
        name: :devices_available_devices_query_update_mode_index
      )
    )

    create_if_not_exists(index(:devices, [:update_mode], concurrently: true))
  end
end
