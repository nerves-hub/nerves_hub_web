defmodule NervesHub.Accounts.Org do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query
  import EctoEnum

  alias NervesHub.Accounts.{OrgKey, OrgUser}
  alias NervesHub.Devices.{Device, CACertificate}
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias __MODULE__

  @params [
    :name,
    :type
  ]

  @type id :: pos_integer() | nil
  @type t :: %__MODULE__{id: id()}

  defenum(Type, :type, [:user, :group])

  schema "orgs" do
    has_many(:org_keys, OrgKey)
    has_many(:products, Product)
    has_many(:devices, Device, where: [deleted_at: nil])
    has_many(:ca_certificates, CACertificate)

    has_many(:org_users, OrgUser, where: [deleted_at: nil])
    has_many(:users, through: [:org_users, :user])

    field(:name, :string)
    field(:type, Type, default: :group)
    field(:deleted_at, :utc_datetime)

    timestamps()
  end

  defp changeset(%Org{} = org, params) do
    org
    |> cast(params, @params)
    |> validate_required(@params)
    |> unique_constraint(:name)
    |> validate_format(:name, ~r/^[A-Za-z0-9-_]+$/)
  end

  def add_user(struct, params) do
    cast(struct, params, [:role])
    |> validate_required([:role])
    |> unique_constraint(
      :org_users,
      name: "org_users_index",
      message: "is already member"
    )
  end

  def change_user_role(struct, params) do
    cast(struct, params, ~w(role)a)
    |> validate_required(~w(role)a)
  end

  def creation_changeset(%Org{} = org, params) do
    org
    |> changeset(params)
  end

  def update_changeset(%Org{} = org, params) do
    org
    |> changeset(params)
  end

  def with_org_keys(%Org{} = o) do
    o
    |> Repo.preload(:org_keys)
  end

  def with_org_keys(org_query) do
    org_query
    |> preload(:org_keys)
  end
end
