defmodule NervesHub.Accounts.User do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.UserToken

  alias NervesHub.Repo

  alias Ecto.Changeset
  alias Ecto.UUID

  alias __MODULE__

  @type t :: %__MODULE__{}

  @password_min_length 8

  @required_params [:name, :email, :password_hash]
  @optional_params [:password, :password_reset_token, :password_reset_token_expires]

  schema "users" do
    has_many(:user_tokens, UserToken)

    has_many(:org_users, OrgUser, where: [deleted_at: nil])
    has_many(:orgs, through: [:org_users, :org], where: [deleted_at: nil])

    # The username column has been repurposed as a name field
    field(:name, :string, source: :username)
    field(:email, :string)
    field(:password, :string, virtual: true)
    field(:password_confirmation, :string, virtual: true)
    field(:password_hash, :string)
    field(:password_reset_token, UUID)
    field(:password_reset_token_expires, :utc_datetime)
    field(:confirmed_at, :naive_datetime)
    field(:deleted_at, :utc_datetime)

    field(:server_role, Ecto.Enum, values: [:admin, :view])

    timestamps()
  end

  defp changeset(%User{} = user, params, opts \\ []) do
    user
    |> cast(params, @required_params ++ @optional_params)
    |> maybe_hash_password(opts)
    |> password_validations()
    |> update_change(:name, &trim/1)
    |> validate_format(:name, ~r/^[a-zA-Z\'\- ]+$/, message: "has invalid character(s)")
    |> validate_required(@required_params)
    |> unique_constraint(:email)
  end

  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:name, :email, :password])
    |> validate_name(opts)
    |> validate_email(opts)
    |> validate_password(opts)
  end

  defp validate_name(changeset, _opts) do
    changeset
    |> update_change(:name, &trim/1)
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 100)
    |> validate_format(:name, ~r/^[a-zA-Z\'\- ]+$/, message: "has invalid character(s)")
  end

  defp validate_email(changeset, _opts) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> unique_constraint(:email)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:password_hash, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  def creation_changeset(%User{} = user, params) do
    changeset(user, params)
    |> validate_required([:password])
  end

  def password_changeset(%User{} = user, params, opts \\ []) do
    user
    |> cast(params, [:password, :password_confirmation])
    |> maybe_hash_password(opts)
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

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%__MODULE__{password_hash: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
  end

  def with_all_orgs(%User{} = u) do
    Repo.preload(u, :orgs)
  end

  def with_all_orgs(user_query) do
    preload(user_query, :orgs)
  end

  def with_org_keys(%User{} = u) do
    Repo.preload(u, orgs: [:org_keys])
  end

  def with_org_keys(user_query) do
    preload(user_query, orgs: [:org_keys])
  end

  def role_or_higher(:view), do: [:view, :manage, :admin]
  def role_or_higher(:manage), do: [:manage, :admin]
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
         "current_password" => curr_pass
       })
       when curr_pass != "" do
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

  @doc """
  The time length that a password reset token is valid.
  Passed to Timex.shift, so it just has to be a keyword list with :minutes, :hours, etc.
  """
  def password_reset_window() do
    [hours: 8]
  end

  defp trim(string) when is_binary(string) do
    string
    |> String.split(" ", trim: true)
    |> Enum.join(" ")
  end

  defp trim(string), do: string
end
