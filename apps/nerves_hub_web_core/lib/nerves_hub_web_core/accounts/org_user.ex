defmodule NervesHubWebCore.Accounts.OrgUser do
  use Ecto.Schema

  import Ecto.Query

  alias NervesHubWebCore.Accounts.{User, Org}

  @type t :: %__MODULE__{}

  schema "org_users" do
    belongs_to(:org, Org)
    belongs_to(:user, User)

    field(:role, User.Role)

    timestamps()
  end

  def with_user(query) do
    preload(query, :user)
  end
end
