defmodule Beamware.Repo.Migrations.Firmware do
  use Ecto.Migration

  def change do
    create table(:tenant_keys) do
      add(:tenant_id, references(:tenants), null: false)

      add(:name, :string, null: false)
      add(:key, :string, null: false)

      timestamps()
    end

    create(
      unique_index(:tenant_keys, [:tenant_id, :name], name: :tenant_keys_tenant_id_name_index)
    )

    create table(:firmwares) do
      add(:tenant_id, references(:tenants), null: false)

      add(:filename, :string, null: false)
      add(:product, :string, null: false)
      add(:platform, :string, null: false)
      add(:architecture, :string, null: false)
      add(:timestamp, :utc_datetime, null: false)
      add(:signed, :boolean, null: false)
      add(:tenant_key_id, references(:tenant_keys))
      add(:metadata, :string, null: false)
      add(:upload_metadata, :map, null: false)

      timestamps()
    end
  end
end
