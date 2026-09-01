defmodule NervesHub.ManagedDeployments.Orchestrator.WorkflowCoordinator do
  @moduledoc """
  Scheduling for a deployment group whose current release carries workflow steps.

  Where `DefaultCoordinator` treats the group as one pool, a workflow walks the
  release's steps in order: only the active step's matching devices are eligible,
  and the step's own concurrency applies rather than the group's.

  A step completing is not the deployment group completing. A deployment group is
  never done — devices keep arriving, and devices that revert fall back out of
  date — so the trailing `:catch_all` step is the steady state: it starts, and
  then stays `:in_progress` for the life of the release, absorbing whatever turns
  up. Only the steps ahead of it complete, and completing is what lets the next
  stage begin.

  Step selection and advancement are in place. Matching devices to a step and
  scheduling them is not yet implemented, so a deployment group with a workflow
  currently schedules nothing.
  """

  use NervesHub.ManagedDeployments.Orchestrator.Coordinator

  alias NervesHub.ManagedDeployments.Orchestrator.Coordinator
  alias NervesHub.ManagedDeployments.Workflows

  require Logger

  @impl Coordinator
  def schedule_updates(deployment_group) do
    case active_step(deployment_group.current_release.steps) do
      nil ->
        false

      step ->
        Logger.info("Workflow step active",
          deployment_id: deployment_group.id,
          step_number: step.number,
          step_type: step.type
        )

        false
    end
  end

  # The step in progress, or the next one waiting to start. Steps arrive ordered by
  # number (see the `:steps` association's `preload_order`).
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
