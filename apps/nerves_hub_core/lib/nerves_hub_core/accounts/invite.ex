defmodule NervesHubCore.Accounts.Invite do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHubCore.Accounts.Org
  alias __MODULE__

  @type t :: %__MODULE__{}

  schema "invites" do
    belongs_to(:org, Org)

    field(:email, :string)
    field(:name, :string)
    field(:token, Ecto.UUID)
    field(:accepted, :boolean)

    timestamps()
  end

  def changeset(%Invite{} = invite, params) do
    invite
    |> cast(params, [:email, :name, :token, :org_id, :accepted])
    |> validate_required([:email, :name, :token, :org_id])
  end
end
