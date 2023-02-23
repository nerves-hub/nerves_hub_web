defmodule NervesHub.Repo.Migrations.FirmwarePatchTable do
  use Ecto.Migration

  def change do
    create table(:firmware_patches) do
      add(:source_id, references(:firmwares, on_delete: :delete_all), null: false)
      add(:target_id, references(:firmwares, on_delete: :delete_all), null: false)

      add(:upload_metadata, :map, null: false)

      timestamps()
    end

    create(
      unique_index(:firmware_patches, [:source_id, :target_id],
        name: :source_id_target_id_unique_index
      )
    )
  end
end
