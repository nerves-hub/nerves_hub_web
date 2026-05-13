defmodule NervesHub.Repo.Migrations.CreateDeviceFirmwares do
  use Ecto.Migration

  def change() do
    create table(:device_firmwares, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:device_id, references(:devices), null: false)
      add(:firmware_id, references(:firmwares), null: true)

      add(:firmware_metadata, :map, null: false, default: %{})
      add(:firmware_validation_status, :string, default: "unknown")
      add(:firmware_auto_revert_detected, :boolean, default: false)

      timestamps(updated_at: false)
    end

    create(index("device_firmwares", [:device_id, desc: :inserted_at]))
  end
end
