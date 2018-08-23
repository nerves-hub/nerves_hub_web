defmodule NervesHubCore.Accounts.User do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias NervesHubCore.Accounts.{Org, UserCertificate}
  alias NervesHubCore.Repo
  alias Comeonin.Bcrypt
  alias Ecto.Changeset
  alias __MODULE__
  alias Ecto.UUID

  @type t :: %__MODULE__{}

  @password_min_length 8

  @required_params [:name, :email, :password_hash]
  @optional_params [:password, :password_reset_token, :password_reset_token_expires]

  schema "users" do
    has_many(:user_certificates, UserCertificate)
    many_to_many(:orgs, Org, join_through: "users_orgs", on_replace: :delete, unique: true)

    field(:name, :string)
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
    |> unique_constraint(:email)
    |> unique_constraint(:orgs, name: :users_orgs_user_id_org_id_index)
  end

  defp handle_orgs(changeset, %{orgs: nil}) do
    changeset |> cast_assoc(:orgs, required: true)
  end

  defp handle_orgs(changeset, %{orgs: orgs}) do
    changeset
    |> put_assoc(:orgs, get_orgs(orgs), required: true)
  end

  defp handle_orgs(changeset, _params) do
    changeset
    |> cast_assoc(:orgs, required: true)
  end

  defp get_orgs(orgs) do
    orgs
    |> Enum.map(fn x -> do_get_org(x) end)
  end

  defp do_get_org(%Org{} = org) do
    org
  end

  defp do_get_org(org) do
    struct(Org, org)
  end

  def creation_changeset(%User{} = user, params) do
    changeset(user, params)
    |> handle_orgs(params)
    |> unique_constraint(:orgs, name: :users_orgs_user_id_org_id_index)
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

  def update_changeset(%User{} = user, %{orgs: _} = params) do
    changeset(user, params)
    |> add_error(:orgs, "update user orgs with update_orgs_changeset/2")
  end

  def update_changeset(%User{} = user, params) do
    changeset(user, params)
    |> generate_password_reset_token_expires()
    |> email_password_update_valid?(user, params)
  end

  def update_orgs_changeset(%User{} = user, params) do
    user
    |> changeset(params)
    |> handle_orgs(params)
  end

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

  defp password_validations(%Changeset{} = changeset) do
    changeset
    |> validate_length(
      :password,
      min: @password_min_length,
      message: "should be at least %{count} characters"
    )
  end

  defp email_password_update_valid?(%Changeset{} = changeset, %User{} = user, %{
         current_password: curr_pass
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
