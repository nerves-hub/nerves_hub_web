defmodule NervesHub.ManagedDeployments.Orchestrator.Coordinator do
  @moduledoc """
  How an orchestrator decides which devices update next.

  A deployment group without a workflow uses `DefaultCoordinator`, which fills the
  group's concurrency slots from one undifferentiated pool. A group whose current
  release carries workflow steps uses `WorkflowCoordinator`, which works one step
  at a time.

  `schedule_updates/1` returns whether the orchestrator should trigger again
  immediately — true when devices were passed over and slots may still be free.
  """

  alias NervesHub.ManagedDeployments.DeploymentGroup

  @callback schedule_updates(DeploymentGroup.t()) :: boolean()

  defmacro __using__(_opts) do
    quote do
      @behaviour NervesHub.ManagedDeployments.Orchestrator.Coordinator

      alias NervesHub.DeviceEvents
      alias NervesHub.Devices.Device
      alias NervesHub.Devices.Updates
      alias NervesHub.ManagedDeployments
      alias NervesHub.ManagedDeployments.DeploymentGroup

      @doc """
      Given a list of devices, confirm they haven't had too many update failures, then
      message the devices to schedule their updates, or update their `blocked_until`.

      Returns the number of devices that were allowed to update.
      """
      @spec schedule_devices!([Device.t()], DeploymentGroup.t(), boolean()) :: non_neg_integer()
      def schedule_devices!(available, deployment_group, priority_queue \\ false) do
        Enum.count(available, fn device ->
          case can_device_update?(device, deployment_group) do
            true ->
              tell_device_to_update(device.id, deployment_group, priority_queue)

            false ->
              _ = Updates.update_blocked_until(device, deployment_group)
              false
          end
        end)
      end

      @spec can_device_update?(Device.t(), DeploymentGroup.t()) :: boolean()
      defp can_device_update?(device, deployment_group) do
        not (Updates.failure_rate_met?(device, deployment_group) or
               Updates.failure_threshold_met?(device, deployment_group))
      end

      @spec tell_device_to_update(integer(), DeploymentGroup.t(), boolean()) :: boolean()
      defp tell_device_to_update(device_id, deployment_group, priority_queue) do
        :telemetry.execute([:nerves_hub, :deployments, :trigger_update, :device], %{count: 1})

        case DeviceEvents.schedule_update(device_id, deployment_group, priority_queue: priority_queue) do
          {:ok, _} -> true
          _ -> false
        end
      end
    end
  end
end
