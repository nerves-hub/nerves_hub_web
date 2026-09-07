defmodule NervesHub.ManagedDeployments.Orchestrator.DefaultCoordinator do
  @moduledoc """
  The scheduling a deployment group gets when it has no workflow: fill the
  priority queue first if it is enabled, then the normal queue, up to the group's
  concurrency limits.
  """

  use NervesHub.ManagedDeployments.Orchestrator.Coordinator

  alias NervesHub.Devices.Updates
  alias NervesHub.FirmwareUpdates
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.Orchestrator.Coordinator

  @impl Coordinator
  def schedule_updates(deployment_group) do
    # Process priority queue first, if enabled
    skipped_priority_updates = maybe_do_priority_update(deployment_group)

    # Process normal queue
    slots = available_slots(deployment_group)

    if slots > 0 do
      available = Updates.available_for_update(deployment_group, slots)
      updated_count = schedule_devices!(available, deployment_group, false)

      length(available) != updated_count or skipped_priority_updates > 0
    else
      false
    end
  end

  # Process priority queue updates for devices below the firmware version threshold.
  # Returns the number of devices that were skipped (not updated).
  @spec maybe_do_priority_update(DeploymentGroup.t()) :: non_neg_integer()

  defp maybe_do_priority_update(%DeploymentGroup{priority_queue_enabled: false}), do: 0

  defp maybe_do_priority_update(deployment_group) do
    priority_slots = available_priority_slots(deployment_group)

    if priority_slots > 0 do
      available = Updates.available_for_priority_update(deployment_group, priority_slots)

      length(available) - schedule_devices!(available, deployment_group, true)
    else
      0
    end
  end

  @doc """
  Determine how many devices should update in the priority queue based on
  the priority queue update limit and the number currently updating in priority queue.
  """
  @spec available_priority_slots(DeploymentGroup.t()) :: non_neg_integer()
  def available_priority_slots(deployment_group) do
    # Just in case inflight goes higher than concurrent, limit it to 0
    (deployment_group.priority_queue_concurrent_updates -
       FirmwareUpdates.count_inflight_priority_updates_for(deployment_group))
    |> max(0)
    |> round()
  end

  @doc """
  Determine how many devices should update based on
  the deployment update limit and the number currently updating
  """
  @spec available_slots(DeploymentGroup.t()) :: non_neg_integer()
  def available_slots(deployment_group) do
    # Just in case inflight goes higher than concurrent, limit it to 0
    (deployment_group.concurrent_updates - FirmwareUpdates.count_inflight_updates_for(deployment_group))
    |> max(0)
    |> round()
  end
end
