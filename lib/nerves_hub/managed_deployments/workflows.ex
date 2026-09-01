defmodule NervesHub.ManagedDeployments.Workflows do
  import Ecto.Query

  alias Ecto.Changeset
  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs.DeploymentGroupTemplates
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Filtering, as: CommonFiltering
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareDelta
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.ManagedDeployments.Orchestrator
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias Phoenix.Channel.Server, as: PhoenixChannelServer

  def start_step(step) do
    started_at = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    changeset = Changeset.change(step, status: :in_progress, started_at: started_at)

    step = Repo.update!(changeset)

    broadcast(step, "step/updated", %{id: step.id, number: step.number, status: step.status})

    step
  end

  defp broadcast(%DeploymentWorkflowStep{deployment_release_id: release_id}, event, payload) do
    PhoenixChannelServer.broadcast(
      NervesHub.PubSub,
      "deployment_release:#{release_id}",
      event,
      payload
    )
  end
end
