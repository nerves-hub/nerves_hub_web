defmodule NervesHub.ManagedDeployments.InflightDeploymentCheck do
  use Ecto.Schema

  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments.DeploymentGroup

  @timestamps_opts updated_at: false

  schema "inflight_deployment_checks" do
    belongs_to(:device, Device)
    belongs_to(:deployment_group, DeploymentGroup, foreign_key: :deployment_id)

    timestamps()
  end
end
