defmodule Beamware.Repo.Migrations.DeploymentStatusToBoolean do
  use Ecto.Migration

  def up do
    alter table(:deployments) do
      remove :status
      add :is_active, :boolean, null: false, default: false
    end
  end

  def down do
    alter table(:deployments) do
      remove :is_active
      add :status, :string, default: "inactive"
    end
  end
end
