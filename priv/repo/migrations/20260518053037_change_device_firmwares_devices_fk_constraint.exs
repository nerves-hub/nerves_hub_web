defmodule NervesHub.Repo.Migrations.ChangeDeviceFirmwaresDevicesFKConstraint do
  use Ecto.Migration

  def up() do
    drop(constraint(:device_firmwares, "device_firmwares_device_id_fkey"))

    alter table(:device_firmwares) do
      modify(:device_id, references(:devices, on_delete: :delete_all))
    end
  end

  def down() do
    drop(constraint(:device_firmwares, "device_firmwares_device_id_fkey"))

    alter table(:device_firmwares) do
      modify(:device_id, references(:devices, on_delete: :nothing))
    end
  end
end
