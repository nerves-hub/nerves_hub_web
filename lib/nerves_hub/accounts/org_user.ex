defmodule NervesHub.Accounts.OrgUser do
  use Ecto.Schema

  import Ecto.Query

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.User

  @type t :: %__MODULE__{}

  schema "org_users" do
    field(:deleted_at, :utc_datetime)
    field(:role, Ecto.Enum, values: [:admin, :manage, :view])

    belongs_to(:org, Org, where: [deleted_at: nil])
    belongs_to(:user, User, where: [deleted_at: nil])

    timestamps()
  end

  def with_user(query) do
    preload(query, :user)
  end
end
