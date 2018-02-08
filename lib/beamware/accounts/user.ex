defmodule Beamware.Accounts.User do
  use Ecto.Schema

  import Ecto.Changeset

  alias Beamware.Accounts.Tenant
  alias Comeonin.Bcrypt
  alias Ecto.Changeset
  alias __MODULE__

  @type t :: %__MODULE__{}

  schema "users" do
    belongs_to :tenant, Tenant

    field :name, :string
    field :email, :string
    field :password, :string, virtual: true
    field :password_hash, :string

    timestamps()
  end

  def creation_changeset(%User{} = user, params) do
    user
    |> cast(params, [:name, :email, :password])
    |> validate_required([:name, :email, :password])
    |> unique_constraint(:email)
    |> hash_password()
  end

  defp hash_password(%Changeset{} = changeset) do
    changeset
    |> get_field(:password)
    |> case do
      nil ->
        changeset

      password ->
        password_hash = Bcrypt.hashpwsalt(password)
        put_change(changeset, :password_hash, password_hash)
    end
  end
end
