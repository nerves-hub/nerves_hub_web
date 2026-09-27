defmodule NervesHub.Accounts.Invite do
  use Ecto.Schema

  import Ecto.Changeset

  alias __MODULE__
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgRole
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.User

  @type t :: %__MODULE__{}

  schema "invites" do
    belongs_to(:org, Org)
    belongs_to(:invited_by, User)

    # Like a member, an invite offers a built-in `role` or a custom `org_role`.
    belongs_to(:org_role, OrgRole)

    field(:email, :string)
    field(:token, Ecto.UUID)
    field(:accepted, :boolean)
    field(:declined_at, :utc_datetime)
    field(:role, Ecto.Enum, values: Ecto.Enum.values(OrgUser, :role))

    timestamps()
  end

  def changeset(%Invite{} = invite, params) do
    invite
    |> cast(params, [:email, :token, :org_id, :accepted, :declined_at, :role, :org_role_id, :invited_by_id])
    |> validate_required([:email, :token, :org_id, :invited_by_id])
    |> OrgRole.validate_assignment()
  end
end
