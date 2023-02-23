defmodule NervesHub.Repo.Migrations.FirmwaresSplitMetadata do
  use Ecto.Migration

  def up do
    alter table(:firmwares) do
      add(:author, :string)
      add(:description, :string)
      add(:misc, :string)
      add(:uuid, :string, null: false)
      add(:vcs_identifier, :string)

      modify(:product, :string, null: true)

      remove(:metadata)
      remove(:timestamp)
    end
  end

  def down do
    alter table(:firmwares) do
      add(:metadata, :string, null: false)
      add(:timestamp, :utc_datetime, null: false)

      modify(:product, :string, null: false)

      remove(:author)
      remove(:description)
      remove(:misc)
      remove(:uuid)
      remove(:vcs_identifier)
    end
  end
end
