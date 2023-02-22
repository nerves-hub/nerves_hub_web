defmodule NervesHubWebCore.Repo.Migrations.FirmwareMustBeSigned do
  use Ecto.Migration

  def up do
    alter table(:firmwares) do
      modify(:tenant_key_id, :bigint, null: false)
      remove(:signed)
    end
  end

  def down do
    alter table(:firmwares) do
      modify(:tenant_key_id, :bigint, null: true)
      add(:signed, :boolean, null: false)
    end
  end
end
