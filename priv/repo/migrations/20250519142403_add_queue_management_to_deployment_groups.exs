defmodule NervesHub.Repo.Migrations.AddQueueManagementToDeploymentGroups do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add(:queue_management, :string, default: "FIFO", null: false)
    end
  end
end
