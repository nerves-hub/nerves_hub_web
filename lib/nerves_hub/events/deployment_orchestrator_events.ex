defmodule NervesHub.DeploymentOrchestratorEvents do
  @moduledoc """
  Encapsulation of events to be sent to the Deployment Orchestrator
  """

  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias Phoenix.Socket.Broadcast

  @group NervesHub.Group

  @doc """
  Join the calling process as the consumer of a deployment group's orchestrator
  events.

  ProcessHub still guarantees a single orchestrator per deployment group;
  joining (rather than registering) lets tests observe the same events.
  """
  @spec subscribe(DeploymentGroup.t()) :: :ok
  def subscribe(deployment_group) do
    :ok = Group.join(@group, key(deployment_group), %{})
  end

  def device_updated(device) do
    broadcast(device, "device-updated", %{})
  end

  def device_online(device, payload) do
    broadcast(device, "device-online", payload)
  end

  def device_added(device) do
    broadcast(device, "device-added", %{})
  end

  def bulk_devices_added(deployment) do
    broadcast(deployment, "bulk-devices-added", %{})
  end

  def deployment_group_deactivated(deployment) do
    broadcast(deployment, "deactivated", %{})
  end

  @doc """
  The `%Broadcast{}` topic these events carry.

  Preserved as the previous `Phoenix.PubSub` topic string, because the
  orchestrator's receivers match on the `"orchestrator:deployment:" <> _`
  prefix. It is not the group key — see `key/1`.
  """
  @spec topic(DeploymentGroup.t() | Device.t() | DeviceInfo.t()) :: String.t()
  def topic(target), do: "orchestrator:deployment:#{deployment_id(target)}"

  defp broadcast(target, event, payload) do
    # Dispatch a %Broadcast{} struct (the same shape PubSub delivered) so the
    # orchestrator's existing handle_info(%Broadcast{...}) clauses are unchanged.
    message = %Broadcast{topic: topic(target), event: event, payload: payload}
    :ok = Group.dispatch(@group, key(target), message)
  end

  # Group key. "/" is Group's hierarchy separator, which keeps the door open for
  # future prefix queries — see the other pub/sub wrappers.
  defp key(target), do: "orchestrator:deployment/#{deployment_id(target)}"

  defp deployment_id(%DeploymentGroup{id: id}), do: id
  defp deployment_id(%Device{deployment_id: id}), do: id
  defp deployment_id(%DeviceInfo{deployment_id: id}), do: id
end
