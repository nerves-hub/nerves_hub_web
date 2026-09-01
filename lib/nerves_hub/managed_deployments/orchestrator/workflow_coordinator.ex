defmodule NervesHub.ManagedDeployments.Orchestrator.WorkflowCoordinator do
  use NervesHub.ManagedDeployments.Orchestrator.Coordinator

  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.Workflows

  def schedule_updates(deployment_group) do
    steps = deployment_group.current_release.steps

    dbg(select_active_step(steps))

    Process.sleep(3_000)

    false
  end

  defp select_active_step(steps) do
    with nil <- Enum.find(steps, &(&1.status == :in_progress)) do
      Enum.find(steps, &(&1.status == :waiting))
      |> Workflows.start_step()
    end
  end
end
