defmodule NervesHub.Repo.Migrations.AddStatusColumnsToDeploymentGroups do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add(:status, :string, default: "ready", null: false)
    end
  end
end
