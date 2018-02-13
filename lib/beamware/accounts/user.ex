defmodule Beamware.Accounts.User do
  use Ecto.Schema

  import Ecto.Changeset

  alias Beamware.Accounts.Tenant
  alias Comeonin.Bcrypt
  alias Ecto.Changeset
  alias __MODULE__

  @type t :: %__MODULE__{}

  schema "users" do
    belongs_to(:tenant, Tenant)

    field(:name, :string)
    field(:email, :string)
    field(:password, :string, virtual: true)
    field(:password_hash, :string)

    timestamps()
  end

  def creation_changeset(%User{} = user, params) do
    user
    |> cast(params, [:name, :email, :password])
    |> validate_required([:name, :email, :password])
    |> unique_constraint(:email)
    |> hash_password()
  end

  def update_changeset(%User{} = user, params) do
    changeset =
      user
      |> cast(params, [:name, :email, :password])
      |> unique_constraint(:email)
      |> hash_password()

    changed = fn(field) -> not (changeset |> get_change(field) |> is_nil()) end
    password_required = (changed.(:password) or changed.(:email))

    cond do
      password_required and params["current_password"] == "" ->
        changeset
        |> Changeset.add_error(:current_password, "can't be blank")

      password_required and not Bcrypt.checkpw(params["current_password"], user.password_hash) ->
        changeset
        |> Changeset.add_error(:current_password, "is invalid")

      true ->
        changeset
    end
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
