defmodule NervesHub.Accounts do
  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi

  alias NervesHub.Accounts.Invite
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgKey
  alias NervesHub.Accounts.OrgMetric
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.RemoveAccount
  alias NervesHub.Accounts.User
  alias NervesHub.Accounts.UserToken
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Products.Product
  alias NervesHub.Accounts.UserNotifier

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

  @spec soft_delete_org(Org.t()) :: {:ok, Org.t()} | {:error, Changeset.t()}
  def soft_delete_org(%Org{} = org) do
    deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

    Multi.new()
    |> Multi.update_all(:soft_delete_products, Ecto.assoc(org, :products),
      set: [deleted_at: deleted_at]
    )
    |> Multi.update(:soft_delete_org, Org.delete_changeset(org))
    |> Repo.transaction()
    |> case do
      {:ok, _result} ->
        {:ok, org}

      {:error, _, changeset, _} ->
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
    %User{}
    |> User.registration_changeset(user_params)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the users password.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(%User{} = user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Updates the Users password.

  ## Examples

      iex> update_user_password(user, "valid password", %{password: ...})
      {:ok, %User{}}

      iex> update_user_password(user, "invalid password", %{password: ...})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(%User{} = user, password, attrs, reset_url) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Repo.update(changeset)
    |> case do
      {:ok, user} ->
        deliver_user_password_updated(user, reset_url)
        {:ok, user}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc ~S"""
  Delivers an email confirming that a users password has been updated.

  ## Examples

      iex> deliver_user_password_updated(user, &url(~p"/reset-password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_password_updated(%User{} = user, reset_url_fun)
      when is_function(reset_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_hashed_token(user, "reset_password", nil)
    Repo.insert!(user_token)
    UserNotifier.deliver_password_updated(user, reset_url_fun.(encoded_token))
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

      maybe_soft_delete_org_user(org_user)

      :ok
    end
  end

  defp maybe_soft_delete_org_user(nil), do: :ok

  defp maybe_soft_delete_org_user(org_user), do: soft_delete_org_user(org_user)

  def soft_delete_org_user(org_user) do
    with {:ok, %{org_id: org_id, user_id: user_id}} <-
           Repo.soft_delete(org_user),
         {_, nil} <- Devices.unpin_org_devices(user_id, org_id) do
      :ok
    else
      err -> err
    end
  end

  def change_org_user_role(%OrgUser{} = ou, role) do
    ou
    |> Org.change_user_role(%{role: role})
    |> Repo.update()
  end

  def get_org_user!(org, user) do
    get_org_user_query(org, user)
    |> Repo.one!()
  end

  def get_org_user(org, user) do
    get_org_user_query(org, user)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      org_user -> {:ok, org_user}
    end
  end

  defp get_org_user_query(org, user) do
    OrgUser
    |> where([ou], ou.org_id == ^org.id)
    |> where([ou], ou.user_id == ^user.id)
    |> join(:inner, [ou], u in assoc(ou, :user), as: :user)
    |> preload([ou, user: user], user: user)
    |> Repo.exclude_deleted()
  end

  def get_org_users(org) do
    from(
      ou in OrgUser,
      where: ou.org_id == ^org.id,
      order_by: [desc: ou.role]
    )
    |> join(:inner, [ou], u in assoc(ou, :user), as: :user)
    |> preload([ou, user: user], user: user)
    |> where([ou, user: user], is_nil(user.deleted_at))
    |> Repo.exclude_deleted()
    |> Repo.all()
  end

  def get_org_admins(org) do
    User
    |> join(:inner, [u], ou in assoc(u, :org_users), as: :memberships)
    |> where(
      [memberships: memberships],
      memberships.role == :admin and
        memberships.org_id == ^org.id and
        is_nil(memberships.deleted_at)
    )
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

  def find_org_user_with_device(user, device_id) do
    OrgUser
    |> join(:left, [ou], o in assoc(ou, :org))
    |> join(:left, [ou, o], p in assoc(o, :products))
    |> join(:left, [ou, o, p], d in assoc(p, :devices))
    |> where([_, _, _, d], d.id == ^device_id)
    |> where([ou], ou.user_id == ^user.id)
    |> where([ou], is_nil(ou.deleted_at))
    |> Repo.one()
  end

  @doc """
  Authenticates a user by their email and password. Returns the user if the
  user is found and the password is correct, otherwise nil.
  """
  @spec authenticate(String.t(), String.t()) ::
          {:ok, User.t()}
          | {:error, :authentication_failed}
  def authenticate(email, password) do
    with {:ok, user} <- get_user_by_email(email),
         true <- Bcrypt.verify_pass(password, user.password_hash) do
      {:ok, user}
    else
      _ ->
        # User wasn't found; do dummy check to make user enumeration more difficult
        Bcrypt.no_user_verify()
        {:error, :authentication_failed}
    end
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
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
    devices =
      Device
      |> select([d], %{
        product_id: d.product_id,
        device_count: count()
      })
      |> Repo.exclude_deleted()
      |> group_by([d], d.product_id)

    products =
      Product
      |> Repo.exclude_deleted()
      |> join(:left, [p], dev in subquery(devices), on: dev.product_id == p.id, as: :devices)
      |> select_merge([_f, devices: devices], %{device_count: devices.device_count})

    User
    |> where(id: ^user_id)
    |> Repo.exclude_deleted()
    |> join(:left, [d], o in assoc(d, :orgs))
    |> join(:left, [d, o], p in subquery(products), on: o.id == p.org_id)
    |> preload([d, o, p], orgs: {o, products: p})
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

  @spec get_orgs() :: [Org.t()]
  def get_orgs() do
    Org
    |> Repo.exclude_deleted()
    |> Repo.all()
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

  def get_org_by_name_and_user!(org_name, %User{id: user_id}) do
    Org
    |> join(:left, [o], u in assoc(o, :users))
    |> where([o], o.name == ^org_name)
    |> where([o, u], u.id == ^user_id)
    |> Repo.exclude_deleted()
    |> Repo.one!()
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

  def list_org_keys(org_or_org_id, load_created_by \\ true)

  def list_org_keys(%Org{id: org_id}, load_created_by) do
    list_org_keys(org_id, load_created_by)
  end

  def list_org_keys(org_id, load_created_by) do
    OrgKey
    |> where(org_id: ^org_id)
    |> then(fn query ->
      if load_created_by do
        preload(query, :created_by)
      else
        query
      end
    end)
    |> order_by(:id)
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

  @spec add_or_invite_to_org(%{required(String.t()) => String.t()}, Org.t(), User.t()) ::
          {:ok, Invite.t()}
          | {:ok, OrgUser.t()}
          | {:error, Changeset.t()}
  def add_or_invite_to_org(%{"email" => email} = params, org, invited_by) do
    case get_user_by_email(email) do
      {:error, :not_found} -> invite(params, org, invited_by)
      {:ok, user} -> add_org_user(org, user, %{role: params["role"]})
    end
  end

  @spec invite(%{email: String.t()}, Org.t(), User.t()) ::
          {:ok, Invite.t()}
          | {:error, Changeset.t()}
  def invite(params, org, invited_by) do
    params =
      Map.merge(params, %{
        "org_id" => org.id,
        "token" => Ecto.UUID.generate(),
        "invited_by_id" => invited_by.id
      })

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
    Invite
    |> where(token: ^token)
    |> where(accepted: false)
    |> where([i], i.inserted_at >= fragment("NOW() - INTERVAL '48 hours'"))
    |> preload(:invited_by)
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
    query =
      Invite
      |> where([i], i.org_id == ^org.id)
      |> where([i], i.token == ^token)
      |> where([i], i.accepted == false)

    with %Invite{} = invite <- Repo.one(query),
         {:ok, invite} <- Repo.delete(invite) do
      {:ok, invite}
    else
      nil ->
        {:error, :not_found}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Inserts a new user record, creating a org and adding a user to
  that new org if needed
  """
  @spec create_user_from_invite(Invite.t(), Org.t(), map()) ::
          {:ok, OrgUser.t()} | {:error, Ecto.Changeset.t()}
  def create_user_from_invite(invite, org, user_params) do
    user_params = Map.put(user_params, "email", invite.email)

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
  Create Base62 encoded user token.

  The core token uses `:crypto.strong_rand_bytes(32)`

  And the final token format is "nh{prefix}_{Base62.encode(token <> crc32(token))}"

  Currently supported prefixes:
    * `u` - User token

  Inspired by [GitHub authentication token formats](https://github.blog/2021-04-05-behind-githubs-new-authentication-token-formats/)
  """
  @spec create_user_session_token(User.t(), String.t() | nil) :: binary()
  def create_user_session_token(%NervesHub.Accounts.User{} = user, note \\ nil) do
    {encoded_token, user_token} = UserToken.build_session_token(user, note)
    Repo.insert!(user_token)
    encoded_token
  end

  @doc """
  Create a 47 character Base64 URL encoded user token.

  Token format is "nh{prefix}_{Base64 encoded :crypto.strong_rand_bytes(32)}"

  Currently supported prefixes:
    * `u` - User token

  Inspired by [GitHub authentication token formats](https://github.blog/2021-04-05-behind-githubs-new-authentication-token-formats/)
  """
  @spec create_user_api_token(User.t(), String.t()) :: String.t()
  def create_user_api_token(%NervesHub.Accounts.User{} = user, note) do
    {encoded_token, user_token} = UserToken.build_hashed_token(user, "api", note)
    Repo.insert!(user_token)
    encoded_token
  end

  @doc """
  Get a UserToken preloaded with the User
  """
  @spec get_user_token(String.t()) :: {:ok, UserToken.t()} | {:error, :not_found}
  def get_user_token("nh" <> _ = friendly_token) do
    with {:ok, query} <- UserToken.verify_api_token_query(friendly_token),
         {%User{}, user_token} <- Repo.one(query) do
      {:ok, user_token}
    else
      _ -> {:error, :not_found}
    end
  end

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

  def get_user_api_tokens(user) do
    UserToken
    |> where(user_id: ^user.id)
    |> where(context: "api")
    |> Repo.all()
  end

  def delete_user_token(user, token_id) do
    {:ok, token} = get_user_token(user, token_id)
    Repo.delete(token)
  end

  @doc """
  Gets the User with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Fetches the user by API token.
  """
  def fetch_user_by_api_token(token) do
    with {:ok, query} <- UserToken.verify_api_token_query(token),
         {user, user_token} <- Repo.one(query) do
      {:ok, user, user_token}
    else
      _ -> :error
    end
  end

  @doc """
  Fetches the user by account confirm token.
  """
  def fetch_user_by_confirm_token(token) do
    with {:ok, query} <- UserToken.verify_account_confirmation_token_query(token),
         {user, user_token} <- Repo.one(query) do
      {:ok, user, user_token}
    else
      _ -> :error
    end
  end

  @doc """
  Update the API token as just used.
  """
  def mark_last_used(user_token) do
    changeset = Ecto.Changeset.change(user_token, %{last_used: DateTime.utc_now(:second)})

    case Repo.update(changeset) do
      {:ok, _user_token} -> :ok
      _ -> :error
    end
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  ## Confirmation

  @doc ~S"""
  Delivers the confirmation email instructions to the given user.

  ## Examples

      iex> deliver_user_confirmation_instructions(user, &url(~p"/confirm/#{&1}"))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_user_confirmation_instructions(confirmed_user, &url(~p"/confirm/#{&1}"))
      {:error, :already_confirmed}

  """
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_hashed_token(user, "confirm", nil)
      Repo.insert!(user_token)
      UserNotifier.deliver_confirmation_instructions(user, confirmation_url_fun.(encoded_token))
    end
  end

  @doc """
  Confirms a user by the given token.

  If the token matches, the user account is marked as confirmed
  and the token is deleted.
  """
  def confirm_user(user) do
    confirm_user_multi(user)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} ->
        {:ok, user}

      {:error, _} ->
        :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["confirm"]))
  end

  ## Reset password

  @doc ~S"""
  Delivers the reset password email to the given user.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &url(~p"/password-reset/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_hashed_token(user, "reset_password", nil)
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
  end

  @doc """
  Gets the user by reset password token.

  ## Examples

      iex> get_user_by_reset_password_token("validtoken")
      %User{}

      iex> get_user_by_reset_password_token("invalidtoken")
      nil

  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_reset_password_token_query(token),
         {%User{} = user, token} <- Repo.one(query),
         true <- UserToken.password_reset_token_still_valid?(token) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user password.

  ## Examples

      iex> reset_user_password(user, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %User{}}

      iex> reset_user_password(user, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

  """
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} ->
        UserNotifier.deliver_reset_password_confirmation(user)

        {:ok, user}

      {:error, :user, changeset, _} ->
        {:error, changeset}
    end
  end
end
