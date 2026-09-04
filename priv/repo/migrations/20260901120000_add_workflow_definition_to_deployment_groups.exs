defmodule NervesHub.Repo.Migrations.AddWorkflowDefinitionToDeploymentGroups do
  use Ecto.Migration

  def change() do
    alter table(:deployments) do
      add(:workflow_definition, :map, null: true)
    end
  end
end
