defmodule NervesHubCore.Accounts.User do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHubCore.Accounts.{Org, UserCertificate}
  alias Comeonin.Bcrypt
  alias Ecto.Changeset
  alias __MODULE__
  alias Ecto.UUID

  @type t :: %__MODULE__{}

  @password_min_length 8

  @required_params [:name, :email, :password_hash]
  @optional_params [:password, :password_reset_token, :password_reset_token_expires]

  schema "users" do
    belongs_to(:org, Org)
    has_many(:user_certificates, UserCertificate)

    field(:name, :string)
    field(:email, :string)
    field(:password, :string, virtual: true)
    field(:password_confirmation, :string, virtual: true)
    field(:password_hash, :string)
    field(:password_reset_token, UUID)
    field(:password_reset_token_expires, :utc_datetime)

    timestamps()
  end

  def creation_changeset(%User{} = user, params) do
    user
    |> cast(params, @required_params ++ @optional_params)
    |> hash_password()
    |> password_validations()
    |> validate_required(@required_params)
    |> unique_constraint(:email)
  end

  def password_changeset(%User{} = user, params) do
    user
    |> cast(params, [:password, :password_confirmation])
    |> hash_password()
    |> password_validations()
    |> validate_confirmation(:password, message: "does not match", required: true)
    |> validate_required([:password_hash])
    |> expire_password_reset_token()
  end

  def update_changeset(%User{} = user, params) do
    creation_changeset(user, params)
    |> generate_password_reset_token_expires()
    |> email_password_update_valid?(user, params)
  end

  defp password_validations(%Changeset{} = changeset) do
    changeset
    |> validate_length(
      :password,
      min: @password_min_length,
      message: "should be at least %{count} characters"
    )
  end

  defp email_password_update_valid?(%Changeset{} = changeset, %User{} = user, %{
         "current_password" => curr_pass
       }) do
    if Bcrypt.checkpw(curr_pass, user.password_hash) do
      changeset
    else
      changeset
      |> add_error(:current_password, "Current password is incorrect.")
    end
  end

  defp email_password_update_valid?(%Changeset{changes: %{password: _}} = changeset, _, _) do
    changeset
    |> add_error(
      :current_password,
      "You must provide a current password in order to change your email or password."
    )
  end

  defp email_password_update_valid?(%Changeset{changes: %{email: _}} = changeset, _, _) do
    changeset
    |> add_error(
      :current_password,
      "You must provide a current password in order to change your email or password."
    )
  end

  defp email_password_update_valid?(%Changeset{} = changeset, _, _), do: changeset

  defp expire_password_reset_token(%Changeset{changes: %{password: _}} = changeset) do
    changeset |> put_change(:password_reset_token_expires, DateTime.utc_now())
  end

  defp expire_password_reset_token(%Changeset{} = changeset), do: changeset

  defp generate_password_reset_token_expires(
         %Changeset{changes: %{password_reset_token: _}} = changeset
       ) do
    changeset
    |> put_change(
      :password_reset_token_expires,
      DateTime.utc_now() |> Timex.shift(password_reset_window())
    )
  end

  defp generate_password_reset_token_expires(%Changeset{} = changeset), do: changeset

  defp hash_password(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    password_hash = Bcrypt.hashpwsalt(password)

    changeset
    |> put_change(:password_hash, password_hash)
    |> put_change(:password_confirmation, nil)
  end

  defp hash_password(changeset), do: changeset

  @doc """
  The time length that a password reset token is valid.
  Passed to Timex.shift, so it just has to be a keyword list with :minutes, :hours, etc.
  """
  def password_reset_window do
    [hours: 8]
  end
end
