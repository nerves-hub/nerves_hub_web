defmodule NervesHub.Accounts.Invite do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.User
  alias __MODULE__

  @type t :: %__MODULE__{}

  schema "invites" do
    belongs_to(:org, Org)
    belongs_to(:invited_by, User)

    field(:email, :string)
    field(:token, Ecto.UUID)
    field(:accepted, :boolean)
    field(:role, Ecto.Enum, values: Ecto.Enum.values(OrgUser, :role))

    timestamps()
  end

  def changeset(%Invite{} = invite, params) do
    invite
    |> cast(params, [:email, :token, :org_id, :accepted, :role, :invited_by_id])
    |> validate_required([:email, :token, :org_id, :role, :invited_by_id])
  end
end
