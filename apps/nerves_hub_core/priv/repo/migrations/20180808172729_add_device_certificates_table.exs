defmodule NervesHubCore.Repo.Migrations.AddDeviceCertificatesTable do
  use Ecto.Migration

  def change do
    create table(:device_certificates) do
      add(:serial, :string, null: false)
      add(:valid_after, :utc_datetime, null: false)
      add(:valid_before, :utc_datetime, null: false)
      add(:device_id, references(:devices, null: false))

      timestamps()
    end

    create(
      unique_index(:device_certificates, [:device_id, :serial], name: :device_certificates_device_id_serial_index)
    )
  end
end
