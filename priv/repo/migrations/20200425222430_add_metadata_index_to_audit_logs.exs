defmodule NervesHub.Repo.Migrations.AddMetadataIndexToAuditLogs do
  use Ecto.Migration

  def up do
    execute("CREATE INDEX audit_param_firmware_uuid ON audit_logs((params->'firmware_uuid'));")
  end

  def down do
    execute("DROP INDEX audit_param_firmware_uuid")
  end
end
