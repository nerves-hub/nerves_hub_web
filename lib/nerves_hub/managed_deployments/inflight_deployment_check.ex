defmodule NervesHub.ManagedDeployments.InflightDeploymentCheck do
  use Ecto.Schema

  @timestamps_opts updated_at: false

  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments.DeploymentGroup

  schema "inflight_deployment_checks" do
    belongs_to(:device, Device)
    belongs_to(:deployment_group, DeploymentGroup, foreign_key: :deployment_id)

    timestamps()
  end
end
