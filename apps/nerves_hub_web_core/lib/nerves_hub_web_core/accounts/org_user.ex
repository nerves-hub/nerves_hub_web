defmodule NervesHubWebCore.Accounts.OrgUser do
  use Ecto.Schema

  import Ecto.Query

  alias NervesHubWebCore.Accounts.{User, Org}

  @type t :: %__MODULE__{}

  schema "org_users" do
    belongs_to(:org, Org, where: [deleted_at: nil])
    belongs_to(:user, User, where: [deleted_at: nil])

    field(:role, User.Role)
    field(:deleted_at, :utc_datetime)

    timestamps()
  end

  def with_user(query) do
    preload(query, :user)
  end
end
