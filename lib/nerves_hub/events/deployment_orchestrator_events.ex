defmodule NervesHub.DeploymentOrchestratorEvents do
  @moduledoc """
  Encapsulation of events to be sent to the Deployment Orchestrator
  """

  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias Phoenix.Channel.Server, as: ChannelServer

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

  def topic(%DeploymentGroup{id: id}) do
    "orchestrator:deployment:#{id}"
  end

  def topic(%Device{deployment_id: id}) do
    "orchestrator:deployment:#{id}"
  end

  defp broadcast(device_or_deployment, event, payload) do
    :ok = ChannelServer.broadcast(NervesHub.PubSub, topic(device_or_deployment), event, payload)
  end
end
