defmodule NervesHub.Repo.Migrations.MoveDeltaUpdatableToDeploymentGroup do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add :delta_updatable, :boolean, default: false
    end

    alter table(:products) do
      remove :delta_updatable
    end
  end

end
