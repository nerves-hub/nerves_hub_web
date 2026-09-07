defmodule NervesHub.Repo.Migrations.CreateDeploymentWorkflowStepsDevices do
  use Ecto.Migration

  def change() do
    create table("deployment_workflow_steps_devices", primary_key: false) do
      add(
        :deployment_workflow_step_id,
        references(:deployment_workflow_steps, on_delete: :delete_all),
        null: false
      )

      add(
        :device_id,
        references(:devices, on_delete: :delete_all),
        null: false
      )

      timestamps()
    end

    create(
      unique_index(:deployment_workflow_steps_devices, [:deployment_workflow_step_id, :device_id],
        name: "deployment_workflow_steps_devices_index"
      )
    )

    # The join table cascades on device deletion, which needs this to avoid a
    # sequential scan per deleted device.
    create(index(:deployment_workflow_steps_devices, [:device_id]))
  end
end
