defmodule NervesHubWeb.AshJsonApiRouter do
  use AshJsonApi.Router,
    domains: [
      NervesHub.Ash.Products,
      NervesHub.Ash.Scripts,
      NervesHub.Ash.Accounts,
      NervesHub.Ash.Devices,
      NervesHub.Ash.Firmwares,
      NervesHub.Ash.Deployments
    ],
    open_api: "/open_api",
    prefix: "/api/v2"
end
