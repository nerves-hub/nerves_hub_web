defmodule Beamware.Accounts.User do
  use Ecto.Schema

  import Ecto.Changeset

  alias Beamware.Accounts.Tenant
  alias Comeonin.Bcrypt
  alias Ecto.Changeset
  alias __MODULE__
  alias Ecto.UUID

  @type t :: %__MODULE__{}

  @password_min_length 8

  schema "users" do
    belongs_to(:tenant, Tenant)

    field(:name, :string)
    field(:email, :string)
    field(:password, :string, virtual: true)
    field(:password_hash, :string)
    field(:password_reset_token, UUID)
    field(:password_reset_token_expires, :utc_datetime)

    timestamps()
  end

  def creation_changeset(%User{} = user, params) do
    user
    |> cast(params, [:name, :email, :password])
    |> validate_required([:name, :email, :password])
    |> unique_constraint(:email)
    |> validate_length(:password, min: @password_min_length)
    |> hash_password()
  end

  def generate_password_reset_token_changeset(%User{} = user) do
    user
    |> change()
    |> put_change(:password_reset_token, UUID.generate())
    |> put_change(
      :password_reset_token_expires,
      DateTime.utc_now() |> Timex.shift(password_reset_window())
    )
  end

  def reset_password_changeset(%User{} = user, params) do
    user
    |> cast(params, [:password])
    |> validate_required([:password])
    |> validate_confirmation(:password)
    |> validate_length(:password, min: @password_min_length)
    |> hash_password()
  end

  def update_changeset(%User{} = user, params) do
    changeset =
      user
      |> cast(params, [:name, :email, :password])
      |> unique_constraint(:email)
      |> hash_password()

    changed = fn field -> not (changeset |> get_change(field) |> is_nil()) end
    password_required = changed.(:password) or changed.(:email)

    cond do
      password_required and params["current_password"] == "" ->
        changeset
        |> add_error(:current_password, "can't be blank")

      password_required and not Bcrypt.checkpw(params["current_password"], user.password_hash) ->
        changeset
        |> add_error(:current_password, "is invalid")

      changed.(:password) ->
        changeset
        |> validate_length(:password, min: @password_min_length)

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

  @doc """
  The time length that a password reset token is valid.
  Passed to Timex.shift, so it just has to be a keyword list with :minutes, :hours, etc.
  """
  def password_reset_window do
    [hours: 8]
  end
end
