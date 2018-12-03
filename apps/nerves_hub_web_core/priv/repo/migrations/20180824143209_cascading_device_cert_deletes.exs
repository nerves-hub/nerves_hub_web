defmodule NervesHubWebCore.Repo.Migrations.CascadingDeviceCertDeletes do
  use Ecto.Migration

  def up do
    drop(constraint(:device_certificates, "device_certificates_device_id_fkey"))

    alter table(:device_certificates) do
      modify(:device_id, references(:devices, on_delete: :delete_all))
    end
  end

  def down do
    drop(constraint(:device_certificates, "device_certificates_device_id_fkey"))

    alter table(:device_certificates) do
      modify(:device_id, references(:devices, on_delete: :nothing))
    end
  end
end
