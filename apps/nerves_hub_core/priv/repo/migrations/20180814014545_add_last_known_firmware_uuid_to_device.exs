defmodule NervesHubCore.Repo.Migrations.AddLastKnownFirmwareUuidToDevice do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add(:last_known_firmware_uuid, :binary_id, null: true)
    end
    create(index(:devices, [:last_known_firmware_uuid]))
  end
end
