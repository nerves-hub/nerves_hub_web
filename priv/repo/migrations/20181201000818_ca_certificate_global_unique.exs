defmodule NervesHub.Repo.Migrations.CaCertificateGlobalUnique do
  use Ecto.Migration

  def up do
    create(
      unique_index(:ca_certificates, [:serial], name: :ca_certificates_serial_index)
    )
    drop(unique_index(:ca_certificates, [:org_id, :serial]))
  end



  def down do
    drop(unique_index(:ca_certificates, [:serial]))
    create(
      unique_index(:ca_certificates, [:org_id, :serial], name: :ca_certificates_org_id_serial_index)
    )
  end
end
