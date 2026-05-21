defmodule NervesHub.Repo.Migrations.AddCurrentDeviceFirmwareToDevices do
  use Ecto.Migration

  def change() do
    alter table(:devices) do
      add(:current_device_firmware_id, references(:device_firmwares, type: :uuid), null: true)
    end
  end
end
