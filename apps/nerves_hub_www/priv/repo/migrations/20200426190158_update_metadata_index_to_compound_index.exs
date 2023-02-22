defmodule NervesHubWebCore.Repo.Migrations.UpdateMetadataIndexToCompoundIndex do
  use Ecto.Migration

  def up do
    execute("DROP INDEX audit_param_firmware_uuid")
    execute("CREATE INDEX audit_param_firmware_uuid_send_update_message ON audit_logs((params->>'firmware_uuid'),(params->>'send_update_message'));")
  end

  def down do
    execute("DROP INDEX audit_param_firmware_uuid_send_update_message")
  end
end
