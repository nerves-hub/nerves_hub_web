defmodule NervesHub.Repo.Migrations.AddCaCertificates do
  use Ecto.Migration

  def change do
    create table(:ca_certificates) do
      add(:org_id, references(:orgs, null: false))
      add(:serial, :string, null: false)
      add(:aki, :binary)
      add(:ski, :binary)
      add(:not_before, :utc_datetime, null: false)
      add(:not_after, :utc_datetime, null: false)
      add(:der, :binary, null: false)
      timestamps()
    end

    create(
      unique_index(:ca_certificates, [:org_id, :serial], name: :ca_certificates_org_id_serial_index)
    )
  end
end
