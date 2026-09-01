defmodule NervesHub.ManagedDeployments.Orchestrator.WorkflowCoordinator do
  @moduledoc """
  Scheduling for a deployment group whose current release carries workflow steps.

  Where `DefaultCoordinator` treats the group as one pool, a workflow walks the
  release's steps in order. One step is active at a time: it claims the devices
  it covers, updates them at its own concurrency, and hands off once they are all
  on the release's firmware.

  A step completing is not the deployment group completing. A deployment group is
  never done — devices keep arriving, and devices that revert fall back out of
  date — so the trailing `:catch_all` step is the steady state: it starts, and
  then stays `:in_progress` for the life of the release, absorbing whatever turns
  up. Only the steps ahead of it complete, and completing is what lets the next
  stage begin.

  A step waits for every device it claimed, including ones that are offline. That
  is the point of a canary stage — declaring it good because its devices could
  not be reached would defeat it — but it does mean a canary that never comes
  back holds the workflow where it is until somebody skips the step.
  """

  use NervesHub.ManagedDeployments.Orchestrator.Coordinator

  alias NervesHub.Devices.Updates
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.ManagedDeployments.Orchestrator.Coordinator
  alias NervesHub.ManagedDeployments.Workflows

  require Logger

  @impl Coordinator
  def schedule_updates(deployment_group) do
    # The orchestrator holds a deployment group for the life of the release, so
    # the steps preloaded on it are a snapshot from before any of this ran.
    deployment_group.current_deployment_release_id
    |> Workflows.release_steps()
    |> active_step()
    |> case do
      nil -> false
      step -> run_step(deployment_group, step)
    end
  end

  # Nothing to schedule while a workflow waits on a person. The step is completed
  # on the pass after somebody approves it, and the orchestrator's periodic
  # trigger is what brings us back to notice.
  defp run_step(deployment_group, %DeploymentWorkflowStep{type: :approval_required} = step) do
    complete_if_done(deployment_group, step, false)
  end

  defp run_step(deployment_group, step) do
    claimed = Workflows.claim_devices(deployment_group, step)

    if claimed > 0 do
      Logger.info("Workflow step claimed devices",
        deployment_id: deployment_group.id,
        step_number: step.number,
        claimed: claimed
      )
    end

    complete_if_done(deployment_group, step, schedule_step_devices(deployment_group, step))
  end

  defp schedule_step_devices(deployment_group, step) do
    slots = Workflows.available_slots(step)

    if slots > 0 do
      available = Updates.available_for_workflow_step(deployment_group, step, slots)
      updated_count = schedule_devices!(available, deployment_group)

      # Some devices were passed over for failures rather than for lack of slots,
      # so there may still be room for others.
      length(available) != updated_count
    else
      false
    end
  end

  # `run_again?` carries whether scheduling alone warrants another pass. A step
  # completing always does, so the next one starts without waiting for the
  # periodic trigger.
  defp complete_if_done(deployment_group, step, run_again?) do
    if Workflows.step_complete?(deployment_group, step) do
      _ = Workflows.complete_step(step)

      Logger.info("Workflow step completed",
        deployment_id: deployment_group.id,
        step_number: step.number,
        step_type: step.type
      )

      true
    else
      run_again?
    end
  end

  # The step in progress, or the next one waiting to start. Steps arrive ordered
  # by number.
  defp active_step(steps) do
    with nil <- Enum.find(steps, &(&1.status == :in_progress)) do
      steps
      |> Enum.find(&(&1.status == :waiting))
      |> case do
        nil -> nil
        step -> Workflows.start_step(step)
      end
    end
  end
end
