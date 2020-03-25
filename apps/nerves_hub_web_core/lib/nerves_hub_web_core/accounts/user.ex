defmodule NervesHubWebCore.Accounts.User do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query
  import EctoEnum

  alias NervesHubWebCore.Accounts.{Org, UserCertificate, OrgUser}
  alias NervesHubWebCore.Repo

  alias Ecto.Changeset
  alias __MODULE__
  alias Ecto.UUID

  @type t :: %__MODULE__{}

  @password_min_length 8

  @required_params [:username, :email, :password_hash]
  @optional_params [:password, :password_reset_token, :password_reset_token_expires]

  defenum(Role, :role, [:admin, :delete, :write, :read])

  schema "users" do
    has_many(:user_certificates, UserCertificate)

    has_many(:org_users, OrgUser)
    has_many(:orgs, through: [:org_users, :org])

    field(:username, :string)
    field(:email, :string)
    field(:password, :string, virtual: true)
    field(:password_confirmation, :string, virtual: true)
    field(:password_hash, :string)
    field(:password_reset_token, UUID)
    field(:password_reset_token_expires, :utc_datetime)

    timestamps()
  end

  defp changeset(%User{} = user, params) do
    user
    |> cast(params, @required_params ++ @optional_params)
    |> hash_password()
    |> password_validations()
    |> validate_required(@required_params)
    |> validate_username()
    |> unique_constraint(:email)
    |> unique_constraint(:username)
  end

  def creation_changeset(%User{} = user, params) do
    changeset(user, params)
    |> validate_required([:password])
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
    changeset(user, params)
    |> generate_password_reset_token_expires()
    |> email_password_update_valid?(user, params)
  end

  defp validate_username(%Changeset{changes: %{username: username}} = changeset) do
    case Regex.match?(~r/^[A-Z,a-z,\d,\-,.,_,~]*$/, username) do
      true -> changeset
      false -> add_error(changeset, :username, "invalid character(s) in username")
    end
  end

  defp validate_username(changeset), do: changeset

  defp default_org_query() do
    # For now just get first inserted org
    from(o in Org) |> first(:inserted_at)
  end

  def with_default_org(%User{} = u) do
    q = default_org_query()

    u
    |> Repo.preload(orgs: q)
  end

  def with_default_org(user_query) do
    q = default_org_query()

    user_query
    |> preload(orgs: ^q)
  end

  def with_all_orgs(%User{} = u) do
    u
    |> Repo.preload(:orgs)
  end

  def with_all_orgs(user_query) do
    user_query
    |> preload(:orgs)
  end

  def with_org_keys(%User{} = u) do
    u
    |> Repo.preload(orgs: [:org_keys])
  end

  def with_org_keys(user_query) do
    user_query
    |> preload(orgs: [:org_keys])
  end

  def role_or_higher(:read), do: [:read, :write, :delete, :admin]
  def role_or_higher(:write), do: [:write, :delete, :admin]
  def role_or_higher(:delete), do: [:delete, :admin]
  def role_or_higher(:admin), do: [:admin]

  defp password_validations(%Changeset{} = changeset) do
    changeset
    |> validate_length(
      :password,
      min: @password_min_length,
      message: "should be at least %{count} characters"
    )
  end

  defp email_password_update_valid?(%Changeset{changes: changes} = changeset, %User{} = user, %{
         current_password: curr_pass
       }) do
    case Map.has_key?(changes, :email) or Map.has_key?(changes, :password) do
      true ->
        if Bcrypt.verify_pass(curr_pass, user.password_hash) do
          changeset
        else
          changeset
          |> add_error(:current_password, "Current password is incorrect.")
        end

      false ->
        changeset
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
    changeset
    |> put_change(
      :password_reset_token_expires,
      DateTime.utc_now()
      |> DateTime.truncate(:second)
    )
  end

  defp expire_password_reset_token(%Changeset{} = changeset), do: changeset

  defp generate_password_reset_token_expires(
         %Changeset{changes: %{password_reset_token: _}} = changeset
       ) do
    changeset
    |> put_change(
      :password_reset_token_expires,
      DateTime.utc_now()
      |> Timex.shift(password_reset_window())
      |> DateTime.truncate(:second)
    )
  end

  defp generate_password_reset_token_expires(%Changeset{} = changeset), do: changeset

  defp hash_password(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    password_hash = Bcrypt.hash_pwd_salt(password)

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
