defmodule NervesHubWeb.GraphqlSchema do
  use Absinthe.Schema

  use AshGraphql,
    domains: [
      NervesHub.Ash.Accounts,
      NervesHub.Ash.Products,
      NervesHub.Ash.Scripts,
      NervesHub.Ash.Devices,
      NervesHub.Ash.Firmwares,
      NervesHub.Ash.Deployments,
      NervesHub.Ash.Archives,
      NervesHub.Ash.AuditLogs
    ]

  query do
  end

  mutation do
  end
end
