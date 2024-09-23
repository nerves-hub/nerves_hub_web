defmodule NervesHub.Workers.DeviceCalculateDeployment do
  use Oban.Worker,
    queue: :device_deployment_calculations,
    max_attempts: 5

  alias NervesHub.Devices.Device
  alias NervesHub.Deployments
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Repo

  @impl true
  def perform(%Oban.Job{args: %{"device_id" => device_id, "deployment_id" => deployment_id}}) do
    device = Repo.get!(Device, device_id)
    deployment = Deployments.get_deployment!(deployment_id) |> Deployment.with_firmware()

    if !is_nil(device.deployment_id) && device.deployment_id != deployment.id do
      :ok
    else
      if deployment.is_active &&
           !is_nil(device.connection_last_seen_at) &&
           device.product_id == deployment.product_id &&
           device.firmware_metadata.platform == deployment.firmware.platform &&
           device.firmware_metadata.architecture == deployment.firmware.architecture &&
           Enum.all?(deployment.conditions["tags"], &Enum.member?(device.tags, &1)) &&
           Deployments.version_match?(device, deployment) do
        device
        |> Ecto.Changeset.change(%{deployment_id: deployment.id})
        |> Repo.update!()
      else
        device
        |> Ecto.Changeset.change(%{deployment_id: nil})
        |> Repo.update!()
      end

      Phoenix.PubSub.broadcast(
        NervesHub.PubSub,
        "device:#{device.id}",
        %Phoenix.Socket.Broadcast{event: "devices/updated"}
      )
    end

    :ok
  end
end
