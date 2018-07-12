defmodule NervesHubCore.Accounts.Invite do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHubCore.Accounts.Tenant
  alias __MODULE__

  @type t :: %__MODULE__{}

  schema "invites" do
    belongs_to(:tenant, Tenant)

    field(:email, :string)
    field(:name, :string)
    field(:token, Ecto.UUID)
    field(:accepted, :boolean)

    timestamps()
  end

  def changeset(%Invite{} = invite, params) do
    invite
    |> cast(params, [:email, :name, :token, :tenant_id, :accepted])
    |> validate_required([:email, :name, :token, :tenant_id])
  end
end
