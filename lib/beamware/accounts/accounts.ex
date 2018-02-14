defmodule Beamware.Accounts do
  import Ecto.Query
  alias Ecto.Changeset
  alias Beamware.Accounts.{Tenant, User, Invite, Email}
  alias Beamware.Repo
  alias Comeonin.Bcrypt

  @doc """
  Create a tenant. Expects `params` to contain fields for both the user and tenant.
  """
  @spec create_tenant(map) ::
          {:ok, Tenant.t()}
          | {:error, Changeset.t()}
  def create_tenant(params) do
    types = %{
      name: :string,
      tenant_name: :string,
      email: :string,
      password: :string
    }

    changeset =
      {%{}, types}
      |> Changeset.cast(params, Map.keys(types))
      |> Changeset.validate_required([
        :name,
        :tenant_name,
        :email,
        :password
      ])

    # Ensure Phoenix.Form shows errors
    changeset = %{changeset | action: :insert}

    changeset
    |> case do
      %Changeset{valid?: false} = changeset ->
        {:error, changeset}

      %Changeset{valid?: true} = changeset ->
        do_create_tenant(changeset)
    end
  end

  @spec do_create_tenant(Changeset.t()) ::
          {:ok, Tenant.t()}
          | {:error, Changeset.t()}
  defp do_create_tenant(tenant_user_changeset) do
    field = fn field_name -> Changeset.get_field(tenant_user_changeset, field_name) end

    tenant_params = %{
      name: field.(:tenant_name)
    }

    user_params = %{
      name: field.(:name),
      email: field.(:email),
      password: field.(:password)
    }

    Repo.transaction(fn ->
      with {:ok, tenant} <- %Tenant{} |> Tenant.changeset(tenant_params) |> Repo.insert(),
           {:ok, _user} <- create_user(tenant, user_params) do
        tenant
      else
        {:error, changeset} ->
          # Merge errors into original changeset
          changeset.errors
          |> Enum.reduce(tenant_user_changeset, fn {key, {message, data}}, changeset ->
            Changeset.add_error(changeset, key, message, data)
          end)
          |> Repo.rollback()
      end
    end)
  end

  @spec create_user(Tenant.t(), map) ::
          {:ok, User.t()}
          | {:error, Changeset.t()}
  def create_user(%Tenant{} = tenant, params) do
    tenant
    |> Ecto.build_assoc(:users)
    |> User.creation_changeset(params)
    |> Repo.insert()
  end

  @doc """
  Authenticates a user by their email and password. Returns the user if the
  user is found and the password is correct, otherwise nil.
  """
  @spec authenticate(String.t(), String.t()) ::
          {:ok, User.t()}
          | {:error, :authentication_failed}
  def authenticate(email, password) do
    email = String.downcase(email)
    user = Repo.get_by(User, email: email)

    with %User{} <- user,
         true <- Bcrypt.checkpw(password, user.password_hash) do
      {:ok, user}
    else
      nil ->
        # User wasn't found; do dummy check to make user enumeration more difficult
        Bcrypt.dummy_checkpw()
        {:error, :authentication_failed}

      false ->
        {:error, :authentication_failed}
    end
  end

  @spec get_user(any()) ::
          {:ok, User.t()}
          | {:error, :not_found}
  def get_user(user_id) do
    query = from(u in User,
                 join: t in assoc(u, :tenant),
                 where: u.id == ^user_id,
                 preload: [tenant: t]
    )

    query
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @spec get_user_with_password_reset_token(String.t()) ::
          {:ok, User.t()}
          | {:error, :not_found}
  def get_user_with_password_reset_token(token) when is_binary(token) do
    query =
      from(
        u in User,
        where: u.password_reset_token == ^token,
        where: u.password_reset_token_expires >= ^DateTime.utc_now()
      )

    query
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @spec get_tenant(number) ::
          {:ok, Tenant.t()}
          | {:error, :not_found}
  def get_tenant(id) do
    Tenant
    |> Repo.get(id)
    |> case do
      nil -> {:error, :not_found}
      tenant -> {:ok, tenant}
    end
  end

  @spec update_tenant(Tenant.t(), map) ::
          {:ok, Tenant.t()}
          | {:error, Changeset.t()}
  def update_tenant(%Tenant{} = tenant, attrs) do
    tenant
    |> Tenant.changeset(attrs)
    |> Repo.update()
  end

  @spec invite(%{name: String.t(), email: String.t()}, Tenant.t()) ::
          {:ok, Invite.t()}
          | {:error, Changeset.t()}
  def invite(params, tenant) do
    params = Map.merge(params, %{"tenant_id" => tenant.id, "token" => Ecto.UUID.generate()})

    %Invite{}
    |> Invite.changeset(params)
    |> Repo.insert()
    |> case do
      {:ok, invite} ->
        Email.send(:invite, invite, tenant)
        {:ok, invite}

      error ->
        error
    end
  end

  @spec get_valid_invite(String.t()) ::
          {:ok, Invite.t()}
          | {:error, :not_found}
  def get_valid_invite(token) do
    query =
      from(
        i in Invite,
        where: i.token == ^token,
        where: i.accepted == false,
        where: i.inserted_at >= fragment("NOW() - INTERVAL '48 hours'")
      )

    query
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      invite -> {:ok, invite}
    end
  end

  @spec create_user_from_invite(Invite.t(), Tenant.t(), map) ::
          {:ok, User.t()}
          | {:error}
  def create_user_from_invite(invite, tenant, user_params) do
    user_params = %{user_params | "email" => invite.email}

    Repo.transaction(fn ->
      with {:ok, user} <- create_user(tenant, user_params),
           {:ok, _invite} <- set_invite_accpted(invite) do
        {:ok, user}
      else
        _ -> {:error}
      end
    end)
  end

  @spec update_user(User.t(), map) ::
          {:ok, User.t()}
          | {:error, Changeset.t()}
  def update_user(%User{} = user, user_params) do
    user
    |> User.update_changeset(user_params)
    |> Repo.update()
  end

  defp set_invite_accpted(invite) do
    invite
    |> Invite.changeset(%{accepted: true})
    |> Repo.update()
  end

  @doc """
  Attempt to send an email with a link for resetting a user's password.
  (If the given email address doesn't correspond to a user, do nothing.

  Returns :ok regardless of the outcome to enforce the business rule
  (at the lowest level) that we should never signal to the user whether
  an email was sent. (Would allow brute force guessing of account emails.)
  """
  @spec send_password_reset_email(String.t()) :: :ok
  def send_password_reset_email(email) when is_binary(email) do
    query = from(u in User, where: u.email == ^email)

    query
    |> Repo.one()
    |> case do
      nil ->
        :ok

      %User{} = user ->
        user
        |> User.generate_password_reset_token_changeset()
        |> Repo.update()
    end
    |> case do
      {:ok, user} ->
        Email.send(:forgot_password, user)
        :ok

      :ok ->
        :ok
    end
  end

  @spec reset_password(String.t(), map) ::
          {:ok, User.t()}
          | {:error, :not_found}
  def reset_password(reset_password_token, params) do
    reset_password_token
    |> get_user_with_password_reset_token()
    |> case do
      {:ok, user} ->
        user
        |> User.reset_password_changeset(params)
        |> Repo.update()

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end
end
