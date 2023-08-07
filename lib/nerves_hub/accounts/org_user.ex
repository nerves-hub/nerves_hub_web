defmodule NervesHub.Accounts.OrgUser do
  use Ecto.Schema

  import Ecto.Query

  alias NervesHub.Accounts.{User, Org}

  @type t :: %__MODULE__{}

  schema "org_users" do
    belongs_to(:org, Org, where: [deleted_at: nil])
    belongs_to(:user, User, where: [deleted_at: nil])

    field(:role, Ecto.Enum, values: [:admin, :delete, :write, :read])
    field(:deleted_at, :utc_datetime)

    timestamps()
  end

  def with_user(query) do
    preload(query, :user)
  end
end
