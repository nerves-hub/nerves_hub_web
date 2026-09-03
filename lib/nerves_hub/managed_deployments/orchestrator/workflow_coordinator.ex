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

  A step that cannot update enough of its devices fails outright rather than
  waiting, and the workflow stops there until somebody retries or skips it. How
  many failures it takes is the step's own `failure_tolerance`.
  """

  use NervesHub.ManagedDeployments.Orchestrator.Coordinator

  alias NervesHub.AuditLogs.DeploymentGroupTemplates
  alias NervesHub.Devices.Updates
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.ManagedDeployments.Orchestrator.Coordinator
  alias NervesHub.ManagedDeployments.Workflows
  alias NervesHub.ProductNotifications

  require Logger

  @impl Coordinator
  def schedule_updates(deployment_group) do
    # The orchestrator holds a deployment group for the life of the release, so
    # the steps preloaded on it are a snapshot from before any of this ran.
    steps = Workflows.release_steps(deployment_group.current_deployment_release_id)

    # A failed step holds the workflow where it is. `active_step/1` looks for one
    # running or waiting, and a failed step is neither, so without this the
    # workflow would step straight over the stage that just went wrong.
    if Enum.any?(steps, &(&1.status == :error)) do
      false
    else
      case active_step(steps) do
        nil -> false
        step -> run_step(deployment_group, step)
      end
    end
  end

  # Nothing to schedule while a workflow waits on a person. The step is completed
  # on the pass after somebody approves it, and the orchestrator's periodic
  # trigger is what brings us back to notice.
  defp run_step(deployment_group, %DeploymentWorkflowStep{type: :approval_required} = step) do
    # Only on the pass that reaches the step; afterwards it is already running and
    # there is nothing new to say.
    if step.status == :in_progress and is_nil(step.approved_at) and just_started?(step) do
      Logger.info("Workflow waiting for approval",
        deployment_id: deployment_group.id,
        step_number: step.number
      )

      announce_halt(deployment_group, step, :awaiting_approval)
    end

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

    if Workflows.step_failed?(deployment_group, step) do
      failed_count = Workflows.failed_device_count(deployment_group, step)

      _ = Workflows.fail_step(step)

      Logger.warning("Workflow step failed",
        deployment_id: deployment_group.id,
        step_number: step.number,
        failed_devices: failed_count,
        tolerance: Workflows.failure_limit(step, Workflows.claimed_device_count(step))
      )

      announce_halt(deployment_group, step, {:failed, failed_count})

      false
    else
      complete_if_done(deployment_group, step, schedule_step_devices(deployment_group, step))
    end
  end

  # A halted workflow is quiet: devices go on connecting, the deployment group
  # still says it is active, and the only sign is a diagram nobody is looking at.
  # So it is said four ways — measured, logged, recorded against the deployment
  # group, and raised to whoever looks after the product.
  defp announce_halt(deployment_group, step, reason) do
    :telemetry.execute(
      [:nerves_hub, :deployments, :workflow, :halted],
      %{count: 1},
      %{
        deployment_id: deployment_group.id,
        step_number: step.number,
        step_type: step.type,
        reason: halt_reason(reason)
      }
    )

    case reason do
      {:failed, failed_count} ->
        DeploymentGroupTemplates.audit_workflow_step_failed(deployment_group, step, failed_count)

      :awaiting_approval ->
        DeploymentGroupTemplates.audit_workflow_awaiting_approval(deployment_group, step)
    end

    _ = ProductNotifications.create_workflow_halted_notification!(deployment_group, step, reason)

    :ok
  end

  defp halt_reason({:failed, _count}), do: :failed
  defp halt_reason(reason), do: reason

  # `start_step/1` stamps `started_at` as it goes, so a step reached on this pass
  # is one whose start is not yet a moment old.
  defp just_started?(%DeploymentWorkflowStep{started_at: nil}), do: false

  defp just_started?(%DeploymentWorkflowStep{started_at: started_at}) do
    NaiveDateTime.diff(NaiveDateTime.utc_now(), started_at, :second) <= 1
  end

  defp schedule_step_devices(deployment_group, step) do
    slots = Workflows.available_slots(deployment_group, step)

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
