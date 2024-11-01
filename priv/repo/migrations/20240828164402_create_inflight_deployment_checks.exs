defmodule NervesHub.Repo.Migrations.CreateInflightDeploymentChecks do
  use Ecto.Migration

  def change do
    create table(:inflight_deployment_checks) do
      add(:device_id, references(:devices), null: false)
      add(:deployment_id, references(:deployments), null: false)

      timestamps(updated_at: false)
    end
  end
end
