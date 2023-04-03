defmodule NervesHub.Repo.Migrations.AddDeploymentIdToDevices do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add(:deployment_id, references(:deployments))
    end
  end
end
