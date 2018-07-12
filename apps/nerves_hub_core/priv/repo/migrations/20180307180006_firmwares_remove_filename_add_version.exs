defmodule NervesHub.Repo.Migrations.FirmwaresRemoveFilenameAddVersion do
  use Ecto.Migration

  def up do
    alter table(:firmwares) do
      remove(:filename)
      add(:version, :string, null: false)
    end
  end

  def down do
    alter table(:firmwares) do
      add(:filename, :string, null: false)
      remove(:version)
    end
  end
end
