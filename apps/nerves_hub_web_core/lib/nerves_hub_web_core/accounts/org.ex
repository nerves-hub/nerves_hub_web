defmodule NervesHubWebCore.Accounts.Org do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias NervesHubWebCore.Accounts.{User, OrgKey, OrgLimit}
  alias NervesHubWebCore.Devices.{Device, CACertificate}
  alias NervesHubWebCore.Products.Product
  alias NervesHubWebCore.Repo
  alias __MODULE__

  @type id :: pos_integer() | nil
  @type t :: %__MODULE__{id: id()}

  schema "orgs" do
    has_many(:org_keys, OrgKey)
    has_many(:products, Product)
    has_many(:devices, Device)
    has_many(:ca_certificates, CACertificate)
    has_one(:org_limits, OrgLimit)

    many_to_many(:users, User, join_through: "users_orgs", on_replace: :delete, unique: true)

    field(:name, :string)

    timestamps()
  end

  defp changeset(%Org{} = org, params) do
    org
    |> cast(params, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name)
    |> unique_constraint(:users, name: :users_orgs_user_id_org_id_index)
  end

  def creation_changeset(%Org{} = org, params) do
    org
    |> changeset(params)
    |> handle_users(params)
  end

  def update_changeset(%Org{} = org, %{users: _} = params) do
    org
    |> changeset(params)
    |> add_error(:users, "update users_orgs with User.update_orgs_changeset/2")
  end

  def update_changeset(%Org{} = org, params) do
    org
    |> changeset(params)
  end

  defp handle_users(changeset, %{users: nil}) do
    changeset |> cast_assoc(:users)
  end

  defp handle_users(changeset, %{users: users}) do
    changeset
    |> put_assoc(:users, get_users(users))
  end

  defp handle_users(changeset, _params) do
    changeset
    |> cast_assoc(:users)
  end

  defp get_users(users) do
    users
    |> Enum.map(fn x -> do_get_user(x) end)
  end

  defp do_get_user(%User{} = user) do
    user
  end

  defp do_get_user(user) do
    struct(User, user)
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
