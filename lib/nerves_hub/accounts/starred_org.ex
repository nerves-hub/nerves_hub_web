defmodule NervesHub.Accounts.StarredOrg do
  @moduledoc """
  An organization a user starred. See `NervesHub.Accounts.Starring`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.StarredOrg
  alias NervesHub.Accounts.User

  @type t :: %__MODULE__{}

  @required [:user_id, :org_id]
  schema "starred_orgs" do
    belongs_to(:user, User)
    belongs_to(:org, Org)

    timestamps(updated_at: false)
  end

  def create(params \\ %{}) do
    %StarredOrg{}
    |> cast(params, @required)
    |> validate_required(@required)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:org_id)
    |> unique_constraint([:user_id, :org_id])
  end
end
