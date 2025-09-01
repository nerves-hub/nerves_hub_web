defmodule NervesHub.Repo.Migrations.AddFirmwareValidatedToDevice do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add(:firmware_validation_status, :string, default: "unknown")
      add(:firmware_auto_revert_detected, :boolean, default: false)
    end
  end
end
