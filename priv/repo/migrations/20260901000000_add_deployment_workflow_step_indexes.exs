defmodule NervesHub.Repo.Migrations.AddDeploymentWorkflowStepIndexes do
  use Ecto.Migration

  def change() do
    # Also serves as the FK index for deployment_release_id, since that is the
    # leading column. Step numbers are what the orchestrator and the UI address a
    # step by, so they have to be unique within a release.
    create(unique_index(:deployment_workflow_steps, [:deployment_release_id, :number]))

    # The join table cascades on device deletion, which needs this to avoid a
    # sequential scan per deleted device.
    create(index(:deployment_workflow_steps_devices, [:device_id]))
  end
end
