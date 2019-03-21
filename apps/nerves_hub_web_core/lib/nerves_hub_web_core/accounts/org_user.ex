defmodule NervesHubWebCore.Accounts.OrgUser do
  use Ecto.Schema

  alias NervesHubWebCore.Accounts.User
  alias NervesHubWebCore.Accounts.Org

  schema "org_users" do
    belongs_to(:org, Org)
    belongs_to(:user, User)

    field(:role, User.Role)

    timestamps()
  end
end
