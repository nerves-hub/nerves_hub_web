defmodule NervesHub.Repo.Migrations.AddFailureToleranceToDeploymentWorkflowSteps do
  use Ecto.Migration

  def change() do
    alter table(:deployment_workflow_steps) do
      add(:failure_tolerance, :map, null: true)
    end
  end
end
