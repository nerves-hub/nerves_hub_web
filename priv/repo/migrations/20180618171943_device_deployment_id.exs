defmodule NervesHub.Repo.Migrations.DeviceDeploymentId do
  use Ecto.Migration

  def up do
    alter table(:devices) do
      add(:target_deployment_id, references(:deployments, on_delete: :nothing), null: true)
      add(:current_firmware_id, references(:firmwares, on_delete: :nothing), null: true)

      remove(:target_version)
      remove(:current_version)
    end
  end

  def down do
    alter table(:devices) do
      add(:target_version, :string, null: true)
      add(:current_version, :string, null: true)

      remove(:target_deployment_id)
      remove(:current_firmware_id)
    end
  end
end
