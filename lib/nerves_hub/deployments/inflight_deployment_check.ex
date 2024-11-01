defmodule NervesHub.Deployments.InflightDeploymentCheck do
  use Ecto.Schema

  @timestamps_opts updated_at: false

  alias NervesHub.Deployments.Deployment
  alias NervesHub.Devices.Device

  schema "inflight_deployment_checks" do
    belongs_to(:device, Device)
    belongs_to(:deployment, Deployment)

    timestamps()
  end
end
