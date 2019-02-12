defmodule NervesHubWebCore.Repo.Migrations.AddDeviceFirmwareMetadataRemoveLastLink do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add :firmware_metadata, :map
      remove :last_known_firmware_id
    end
  end
end
