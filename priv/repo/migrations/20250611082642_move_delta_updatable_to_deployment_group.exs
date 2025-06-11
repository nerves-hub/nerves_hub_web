defmodule NervesHub.Repo.Migrations.MoveDeltaUpdatableToDeploymentGroup do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add :delta_updatable, :boolean, default: false
    end
  end
end
