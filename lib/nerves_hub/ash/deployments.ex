defmodule NervesHub.Ash.Deployments do
  use Ash.Domain,
    extensions: [AshJsonApi.Domain, AshGraphql.Domain]

  resources do
    resource NervesHub.Ash.Deployments.DeploymentGroup
    resource NervesHub.Ash.Deployments.DeploymentRelease
    resource NervesHub.Ash.Deployments.InflightDeploymentCheck
  end
end
