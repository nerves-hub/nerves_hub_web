defmodule NervesHub.ManagedDeployments.InflightDeploymentCheck do
  use Ecto.Schema

  @timestamps_opts updated_at: false

  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Devices.Device

  schema "inflight_deployment_checks" do
    belongs_to(:device, Device)
    belongs_to(:deployment_group, DeploymentGroup, foreign_key: :deployment_id)

    timestamps()
  end
end
