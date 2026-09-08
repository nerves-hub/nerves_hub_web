defmodule NervesHub.Repo.Migrations.AddAkiIndexToDeviceCertificates do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change() do
    # Signer CA lookups match `device_certificates.aki` against
    # `ca_certificates.ski`, both to count the devices using a CA and to filter
    # the device list by one. Include `device_id` so the counts can be answered
    # from the index alone.
    create(index(:device_certificates, [:aki, :device_id], concurrently: true))
  end
end
