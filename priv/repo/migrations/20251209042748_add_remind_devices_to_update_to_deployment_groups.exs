defmodule NervesHub.Repo.Migrations.AddRemindDevicesToUpdateToDeploymentGroups do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add(:remind_devices_to_update, :boolean, default: false)
    end
  end
end
