defmodule NervesHub.Ash.Accounts do
  use Ash.Domain,
    extensions: [AshJsonApi.Domain, AshGraphql.Domain]

  resources do
    resource NervesHub.Ash.Accounts.Org
    resource NervesHub.Ash.Accounts.OrgUser
    resource NervesHub.Ash.Accounts.OrgKey
    resource NervesHub.Ash.Accounts.User
    resource NervesHub.Ash.Accounts.Invite
    resource NervesHub.Ash.Accounts.OrgMetric
    resource NervesHub.Ash.Accounts.UserToken
  end
end
