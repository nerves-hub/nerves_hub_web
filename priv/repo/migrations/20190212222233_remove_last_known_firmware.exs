defmodule NervesHubWebCore.Repo.Migrations.RemoveLastKnownFirmware do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      remove(:last_known_firmware_id)
    end
  end
end
