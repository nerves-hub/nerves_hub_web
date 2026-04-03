defmodule NervesHub.Repo.Migrations.ImproveAvailableDevicesQueryIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change() do
    create_if_not_exists(
      index(
        :devices,
        [
          :deployment_id,
          :updates_enabled,
          :firmware_validation_status,
          "COALESCE(updates_blocked_until, '1970-01-01 00:00:00'::timestamp)"
        ],
        where: "firmware_metadata IS NOT NULL",
        concurrently: true,
        name: :devices_available_devices_query_index
      )
    )

    create_if_not_exists(
      index(
        :deployments,
        [:current_deployment_release_id],
        where: "is_active = true AND status = 'ready'",
        concurrently: true,
        name: :deployments_current_release_id_active_and_ready_index
      )
    )

    create_if_not_exists(
      index(
        :device_connections,
        [:id],
        where: "status = 'connected'",
        concurrently: true,
        name: :device_connections_id_status_is_connected_index
      )
    )
  end
end
