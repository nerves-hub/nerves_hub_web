defmodule NervesHub.Repo.Migrations.ChangeInflightUpdateFirmwareColumns do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change() do
    alter table(:inflight_updates) do
      modify(:firmware_id, :integer, null: true)
      modify(:firmware_uuid, :uuid, null: true)
    end
  end
end
