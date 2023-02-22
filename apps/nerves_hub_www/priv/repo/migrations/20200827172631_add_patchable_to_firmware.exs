defmodule NervesHubWebCore.Repo.Migrations.AddPatchableToFirmware do
  use Ecto.Migration

  def change do
    alter table(:firmwares) do
      add(:patchable, :boolean, default: false)
    end
  end
end
