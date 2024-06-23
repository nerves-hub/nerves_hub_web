defmodule NervesHub.Accounts do
  import Ecto.Query

  alias Ecto.{Changeset, Multi}
  alias Ecto.UUID

  alias NervesHub.Accounts.{
    Org,
    User,
    UserToken,
    Invite,
    OrgKey,
    OrgUser,
    OrgMetric,
    RemoveAccount
  }

  alias NervesHub.Products.Product

  alias NervesHub.Repo

  @spec create_org(User.t(), map) ::
          {:ok, Org.t()}
          | {:error, Changeset.t()}
  def create_org(%User{} = user, params) do
    multi =
      Multi.new()
      |> Multi.insert(:org, Org.creation_changeset(%Org{}, params))
      |> Multi.insert(:org_user, fn %{org: org} ->
        org_user = %OrgUser{
          org_id: org.id,
          user_id: user.id,
          role: :admin
        }

        Org.add_user(org_user, %{})
      end)

    case Repo.transaction(multi) do
      {:ok, result} ->
        {:ok, result.org}

      {:error, :org, changeset, _} ->
        {:error, changeset}
    end
  end

  def change_user(user, params \\ %{})

  def change_user(%User{id: nil} = user, params) do
    User.creation_changeset(user, params)
  end

  def change_user(%User{} = user, params) do
    User.update_changeset(user, params)
  end

  @doc """
  Creates a new user, and an org if one does not exist yet
  """
  @spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def create_user(user_params) do
    org_params = %{name: user_params[:username]}

    multi =
      Multi.new()
      |> Multi.insert(:user, User.creation_changeset(%User{}, user_params))
      |> Multi.insert(:org, Org.creation_changeset(%Org{}, org_params))
      |> Multi.insert(:org_user, fn %{user: user, org: org} ->
        org_user = %OrgUser{
          org_id: org.id,
          user_id: user.id,
          role: :admin
        }

        Org.add_user(org_user, %{})
      end)

    case Repo.transaction(multi) do
      {:ok, result} ->
        {:ok, result.user}

      {:error, :user, changeset, _} ->
        {:error, changeset}
    end
  end

  @doc """
  Adds a user to an org.
  `params` are passed to `Org.add_user/2`.
  """
  @spec add_org_user(Org.t(), User.t(), map()) ::
          {:ok, OrgUser.t()} | {:error, Ecto.Changeset.t()}
  def add_org_user(%Org{} = org, %User{} = user, params) do
    org_user = %OrgUser{org_id: org.id, user_id: user.id}

    multi =
      Multi.new()
      |> Multi.insert(:org_user, Org.add_user(org_user, params))

    case Repo.transaction(multi) do
      {:ok, result} ->
        {:ok, Repo.preload(result.org_user, :user)}

      {:error, :org_user, changeset, _} ->
        {:error, changeset}
    end
  end

  def remove_org_user(%Org{} = org, %User{} = user) do
    count = Repo.aggregate(Ecto.assoc(org, :org_users), :count, :id)

    if count == 1 do
      {:error, :last_user}
    else
      org_user = Repo.get_by(Ecto.assoc(org, :org_users), user_id: user.id)

      if org_user do
        {:ok, _result} = Repo.soft_delete(org_user)
      end

      :ok
    end
  end

  def change_org_user_role(%OrgUser{} = ou, role) do
    ou
    |> Org.change_user_role(%{role: role})
    |> Repo.update()
  end

  def get_org_user(org, user) do
    OrgUser
    |> where([ou], ou.org_id == ^org.id)
    |> where([ou], ou.user_id == ^user.id)
    |> OrgUser.with_user()
    |> Repo.exclude_deleted()
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      org_user -> {:ok, org_user}
    end
  end

  def get_org_users(org) do
    from(
      ou in OrgUser,
      where: ou.org_id == ^org.id,
      order_by: [desc: ou.role]
    )
    |> join(:inner, [ou], u in assoc(ou, :user), as: :user)
    |> where([ou, user: user], is_nil(user.deleted_at))
    |> OrgUser.with_user()
    |> Repo.exclude_deleted()
    |> Repo.all()
  end

  def has_org_role?(org, user, role) do
    from(
      ou in OrgUser,
      where: ou.org_id == ^org.id,
      where: ou.user_id == ^user.id,
      where: ou.role in ^User.role_or_higher(role),
      where: is_nil(ou.deleted_at),
      select: count(ou.id) >= 1
    )
    |> Repo.one()
  end

  def get_user_orgs(%User{} = user) do
    query =
      from(
        o in Org,
        full_join: ou in OrgUser,
        on: ou.org_id == o.id,
        where: ou.user_id == ^user.id,
        where: is_nil(ou.deleted_at),
        group_by: o.id
      )

    query
    |> Repo.exclude_deleted()
    |> Repo.all()
  end

  @doc """
  Authenticates a user by their email and password. Returns the user if the
  user is found and the password is correct, otherwise nil.
  """
  @spec authenticate(String.t(), String.t()) ::
          {:ok, User.t()}
          | {:error, :authentication_failed}
  def authenticate(email_or_username, password) do
    with {:ok, user} <- get_user_by_email_or_username(email_or_username),
         true <- Bcrypt.verify_pass(password, user.password_hash) do
      {:ok, user |> User.with_default_org() |> User.with_org_keys()}
    else
      _ ->
        # User wasn't found; do dummy check to make user enumeration more difficult
        Bcrypt.no_user_verify()
        {:error, :authentication_failed}
    end
  end

  @spec get_user(integer()) ::
          {:ok, User.t()}
          | {:error, :not_found}
  def get_user(user_id) do
    query = from(u in User, where: u.id == ^user_id)

    query
    |> Repo.exclude_deleted()
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  def get_user!(user_id) do
    User
    |> Repo.exclude_deleted()
    |> Repo.get!(user_id)
  end

  def get_user_with_all_orgs_and_products(user_id) do
    org_query = from(o in Org, where: is_nil(o.deleted_at))
    product_query = from(p in Product, where: is_nil(p.deleted_at))

    orgs_preload = {org_query, products: product_query}

    User
    |> where([u], u.id == ^user_id)
    |> Repo.exclude_deleted()
    |> preload(orgs: ^orgs_preload)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  def get_user_by_email(email) do
    User
    |> Repo.exclude_deleted()
    |> Repo.get_by(email: email)
    |> case do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  def get_user_by_username(username) do
    User
    |> Repo.exclude_deleted()
    |> Repo.get_by(username: username)
    |> case do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  def get_user_by_email_or_username(email_or_username) do
    User
    |> Repo.exclude_deleted()
    |> where(username: ^email_or_username)
    |> or_where(email: ^email_or_username)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      cert -> {:ok, cert}
    end
  end

  @doc """
  Gets a user via a password reset token string.
  Checks validity and equivelence, returning `{:ok, %User{}}` or `{:error, :not_found}`
  """
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

  @spec get_org(integer()) ::
          {:ok, Org.t()}
          | {:error, :org_not_found}
  def get_org(id) do
    Org
    |> Repo.exclude_deleted()
    |> Repo.get(id)
    |> case do
      nil -> {:error, :org_not_found}
      org -> {:ok, org}
    end
  end

  def get_org!(id) do
    Org
    |> Repo.exclude_deleted()
    |> Repo.get!(id)
  end

  def get_org_with_org_keys(id) do
    Org
    |> Repo.exclude_deleted()
    |> Repo.get(id)
    |> case do
      nil -> {:error, :not_found}
      org -> {:ok, org |> Org.with_org_keys()}
    end
  end

  def get_org_by_name(org_name) do
    Org
    |> Repo.exclude_deleted()
    |> Repo.get_by(name: org_name)
    |> case do
      nil -> {:error, :org_not_found}
      org -> {:ok, org}
    end
  end

  def get_org_by_name_and_user(org_name, %User{id: user_id}) do
    query =
      from(
        o in Org,
        join: u in assoc(o, :users),
        where: u.id == ^user_id and o.name == ^org_name
      )

    query
    |> Repo.exclude_deleted()
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      org -> {:ok, org}
    end
  end

  @spec update_org(Org.t(), map) ::
          {:ok, Org.t()}
          | {:error, Changeset.t()}
  def update_org(%Org{} = org, attrs) do
    org
    |> Org.update_changeset(attrs)
    |> Repo.update()
  end

  @spec create_org_key(map) ::
          {:ok, OrgKey.t()}
          | {:error, Changeset.t()}
  def create_org_key(attrs) do
    %OrgKey{}
    |> change_org_key(attrs)
    |> Repo.insert()
  end

  def list_org_keys(%Org{id: org_id}) do
    query = from(tk in OrgKey, where: tk.org_id == ^org_id)

    query
    |> Repo.all()
  end

  def get_org_key(%Org{id: org_id}, tk_id) do
    get_org_key_query(org_id, tk_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      key -> {:ok, key}
    end
  end

  def get_org_key!(%Org{id: org_id}, tk_id) do
    get_org_key_query(org_id, tk_id)
    |> Repo.one!()
  end

  defp get_org_key_query(org_id, tk_id) do
    from(
      tk in OrgKey,
      where: tk.org_id == ^org_id,
      where: tk.id == ^tk_id
    )
  end

  def get_org_key_by_name(%Org{id: org_id}, name) do
    query =
      from(
        k in OrgKey,
        where: k.org_id == ^org_id,
        where: k.name == ^name
      )

    query
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      key -> {:ok, key}
    end
  end

  def update_org_key(%OrgKey{} = org_key, params) do
    org_key
    |> change_org_key(params)
    |> Repo.update()
  end

  def delete_org_key(%OrgKey{} = org_key) do
    org_key
    |> OrgKey.delete_changeset(%{})
    |> Repo.delete()
  end

  def change_org_key(org_key, params \\ %{})

  def change_org_key(%OrgKey{id: nil} = org_key, params) do
    OrgKey.changeset(org_key, params)
  end

  def change_org_key(%OrgKey{id: _id} = org_key, params) do
    OrgKey.update_changeset(org_key, params)
  end

  @spec add_or_invite_to_org(%{required(String.t()) => String.t()}, Org.t()) ::
          {:ok, Invite.t()}
          | {:ok, OrgUser.t()}
          | {:error, Changeset.t()}
  def add_or_invite_to_org(%{"email" => email} = params, org) do
    case get_user_by_email(email) do
      {:error, :not_found} -> invite(params, org)
      {:ok, user} -> invite(params, org)
        # add_org_user(org, user, %{role: params["role"]})
    end
  end

  @spec invite(%{email: String.t()}, Org.t()) ::
          {:ok, Invite.t()}
          | {:error, Changeset.t()}
  def invite(params, org) do
    params = Map.merge(params, %{"org_id" => org.id, "token" => Ecto.UUID.generate()})

    %Invite{}
    |> Invite.changeset(params)
    |> Repo.insert()
  end

  @doc """
  Gets an invite via it's token, checking validity within 48 hours.

  Returns `{:ok, %Invite{}}` or `{:error, :invite_not_found}`
  """
  @spec get_valid_invite(String.t()) ::
          {:ok, Invite.t()}
          | {:error, :invite_not_found}
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
      nil -> {:error, :invite_not_found}
      invite -> {:ok, invite}
    end
  end

  def get_invites_for_org(org) do
    Invite
    |> where([i], i.org_id == ^org.id)
    |> where([i], i.accepted == false)
    |> Repo.all()
  end

  def delete_invite(org, token) do
    Invite
    |> where([i], i.org_id == ^org.id)
    |> where([i], i.token == ^token)
    |> where([i], i.accepted == false)
    |> Repo.one()
    |> Repo.delete()
  end

  @doc """
  Inserts a new user record, creating a org and adding a user to
  that new org if needed
  """
  @spec create_user_from_invite(Invite.t(), Org.t(), map()) ::
          {:ok, OrgUser.t()} | {:error, Ecto.Changeset.t()}
  def create_user_from_invite(invite, org, user_params) do
    user_params = Map.put(user_params, :email, invite.email)

    Repo.transaction(fn ->
      with {:ok, user} <- create_user(user_params),
           {:ok, user} <- add_org_user(org, user, %{role: invite.role}),
           {:ok, _invite} <- set_invite_accepted(invite) do
        # Repo.transaction will wrap this in an {:ok, user}
        user
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
  end

  @spec update_user(User.t(), map) ::
          {:ok, User.t()}
          | {:error, Changeset.t()}
  def update_user(%User{} = user, user_params) do
    user
    |> change_user(user_params)
    |> Repo.update()
  end

  @spec set_invite_accepted(Invite.t()) :: {:ok, Invite.t()} | {:error, Ecto.Changeset.t()}
  defp set_invite_accepted(invite) do
    invite
    |> Invite.changeset(%{accepted: true})
    |> Repo.update()
  end

  @doc """
  Sets the `password_reset_token` field on the user struct

  returns one of:
    * `{:error, :no_user}` if the user couldn't be found by `email`
    * `{:ok, %User{}}` if the `update` was successful
    * `{:error, %Ecto.Changeset{}}` if the `update` failed
  """
  @spec update_password_reset_token(String.t()) ::
          {:ok, User.t()} | {:error, :no_user} | {:error, Ecto.Changeset.t()}
  def update_password_reset_token(email) when is_binary(email) do
    query = from(u in User, where: u.email == ^email)

    query
    |> Repo.one()
    |> case do
      nil ->
        {:error, :no_user}

      %User{} = user ->
        user
        |> change_user(%{password_reset_token: UUID.generate()})
        |> Repo.update()
    end
  end

  @doc """
  Updates a users password via the `User.password_changeset`

  returns one of:
    * `{:error, :no_user}` if the user couldn't be found by `email`
    * `{:ok, %User{}}` if the `update` was successful
    * `{:error, %Ecto.Changeset{}}` if the `update` failed
  """
  @spec reset_password(String.t(), map) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  def reset_password(reset_password_token, params) do
    with {:ok, user} <- get_user_with_password_reset_token(reset_password_token) do
      user
      |> User.password_changeset(params)
      |> Repo.update()
    end
  end

  @spec user_in_org?(integer(), integer()) :: boolean()
  def user_in_org?(user_id, org_id) do
    from(ou in OrgUser,
      where: ou.user_id == ^user_id and ou.org_id == ^org_id,
      select: %{}
    )
    |> Repo.one()
    |> case do
      nil -> false
      _ -> true
    end
  end

  def create_org_metrics(run_utc_time) do
    query =
      from(
        o in Org,
        select: o.id
      )

    today = Date.utc_today()

    case DateTime.from_iso8601("#{today}T#{run_utc_time}Z") do
      {:ok, timestamp, _} ->
        query
        |> Repo.exclude_deleted()
        |> Repo.all()
        |> Enum.each(&create_org_metric(&1, timestamp))

      error ->
        error
    end
  end

  def create_org_metric(org_id, timestamp) do
    devices = NervesHub.Devices.get_device_count_by_org_id(org_id)

    bytes_stored =
      NervesHub.Firmwares.get_firmware_by_org_id(org_id)
      |> Enum.reduce(0, &(&1.size + &2))

    params = %{
      org_id: org_id,
      devices: devices,
      bytes_stored: bytes_stored,
      timestamp: timestamp
    }

    %OrgMetric{}
    |> OrgMetric.changeset(params)
    |> Repo.insert()
  end

  defdelegate remove_account(user_id), to: RemoveAccount

  @doc """
  Create a 36 digit Base62 encoded user token

  Token format is "nh{prefix}_{30 digit HMAC}{6 digit 32 bit CRC32 checksum}"

  Currently supported prefixes:
    * `u` - User token

  Heavily inspired by [GitHub authentication token formats](https://github.blog/2021-04-05-behind-githubs-new-authentication-token-formats/)
  """
  @spec create_user_token(User.t(), String.t()) ::
          {:ok, UserToken.t()} | {:error, Ecto.Changeset.t()}
  def create_user_token(%NervesHub.Accounts.User{} = user, note) do
    UserToken.create_changeset(user, %{note: note})
    |> Repo.insert()
  end

  @doc """
  Get a UserToken preloaded with the User
  """
  @spec get_user_token(String.t()) :: {:ok, UserToken.t()} | {:error, :not_found}
  def get_user_token(token) do
    from(UserToken, where: [token: ^token], preload: [:user])
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      ut -> {:ok, ut}
    end
  end

  def get_user_token(user, id) do
    case Repo.get_by(UserToken, id: id, user_id: user.id) do
      nil ->
        {:error, :not_found}

      user_token ->
        {:ok, user_token}
    end
  end
end
