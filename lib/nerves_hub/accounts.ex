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
  alias NervesHub.Accounts.Scope
  alias NervesHub.Accounts.User
  alias NervesHub.Accounts.UserCLISession
  alias NervesHub.Accounts.UserNotifier
  alias NervesHub.Accounts.UserToken
  alias NervesHub.CLISessionCache
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias NervesHubWeb.Endpoint

  @mfa_secret_salt "user mfa secret"
  @mfa_recovery_code_count 10

  @spec create_org(User.t(), map) ::
          {:ok, Org.t()}
          | {:error, Changeset.t()}
  def create_org(%User{} = user, params) do
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
    |> Repo.transact()
    |> case do
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
    |> Multi.update_all(:soft_delete_products, Ecto.assoc(org, :products), set: [deleted_at: deleted_at])
    |> Multi.update(:soft_delete_org, Org.delete_changeset(org))
    |> Repo.transact()
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
  Generates default onboarding names for a new user based on their name.

  Slugifies the user's name to create suggested names:
  - An org named `<slug>-team`
  - A product named `<slug>ifier`

  Returns `{org_name, product_name}`.
  """
  @spec generate_onboarding_names(String.t()) :: {String.t(), String.t()}
  def generate_onboarding_names(user_name) do
    slug = slugify_name(user_name)
    {"#{slug}-team", "#{slug}ifier"}
  end

  defp slugify_name(name) do
    case Slug.slugify(name) do
      nil -> "user-#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"
      slug -> slug
    end
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
        _ = deliver_user_password_updated(user, reset_url)
        {:ok, user}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def start_mfa_setup(%User{} = user, current_password) do
    if User.valid_password?(user, current_password) do
      secret = NimbleTOTP.secret()
      issuer = mfa_issuer()
      label = "#{issuer}:#{user.email}"
      otpauth_uri = NimbleTOTP.otpauth_uri(label, secret, issuer: issuer)

      {:ok,
       %{
         secret: secret,
         otpauth_uri: otpauth_uri,
         qr_svg: otpauth_uri |> EQRCode.encode() |> EQRCode.svg(width: 240),
         manual_key: Base.encode32(secret, padding: false)
       }}
    else
      {:error, :invalid_password}
    end
  end

  def confirm_mfa_setup(%User{} = user, secret, code) when is_binary(secret) and is_binary(code) do
    if used_at = accepted_totp_time(secret, code) do
      recovery_codes = generate_recovery_codes()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Multi.new()
      |> Multi.update(
        :user,
        Changeset.change(user, %{
          mfa_enabled_at: now,
          mfa_last_used_at: used_at,
          mfa_secret: encrypt_mfa_secret(secret),
          mfa_recovery_codes: Enum.map(recovery_codes, &Bcrypt.hash_pwd_salt/1)
        })
      )
      |> Multi.run(:session_tokens, fn repo, _ ->
        session_tokens = repo.all(UserToken.by_user_and_contexts_query(user, ["session"]))

        Enum.each(session_tokens, fn session_token ->
          Endpoint.broadcast("users_sessions:#{Base.url_encode64(session_token.token)}", "disconnect", %{})
        end)

        {deleted_count, _} = repo.delete_all(UserToken.by_user_and_contexts_query(user, ["session"]))

        {:ok, deleted_count}
      end)
      |> Repo.transact()
      |> case do
        {:ok, %{user: user}} -> {:ok, user, recovery_codes}
        {:error, :user, changeset, _} -> {:error, changeset}
      end
    else
      {:error, :invalid_code}
    end
  end

  def verify_mfa_code(user, code, opts \\ [])

  def verify_mfa_code(%User{mfa_enabled_at: nil}, _code, _opts), do: {:error, :mfa_not_enabled}

  def verify_mfa_code(%User{} = user, code, opts) when is_binary(code) do
    Repo.transact(fn ->
      user =
        User
        |> where(id: ^user.id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      case decrypt_mfa_secret(user.mfa_secret) do
        {:ok, secret} ->
          cond do
            used_at = accepted_totp_time(secret, code, Keyword.put(opts, :since, user.mfa_last_used_at)) ->
              mark_mfa_used(user, used_at)
              {:ok, :totp}

            recovery_code_format?(code) ->
              consume_recovery_code(user, code)

            true ->
              Repo.rollback(:invalid_code)
          end

        :error ->
          Repo.rollback(:invalid_code)
      end
    end)
    |> case do
      {:ok, method} -> {:ok, method}
      {:error, :invalid_code} -> {:error, :invalid_code}
    end
  end

  def disable_mfa(%User{} = user, current_password) do
    if User.valid_password?(user, current_password) do
      user
      |> Changeset.change(%{
        mfa_enabled_at: nil,
        mfa_last_used_at: nil,
        mfa_secret: nil,
        mfa_recovery_codes: []
      })
      |> Repo.update()
    else
      {:error, :invalid_password}
    end
  end

  def mfa_enabled?(%User{mfa_enabled_at: enabled_at}), do: not is_nil(enabled_at)

  defp accepted_totp_time(secret, code, opts \\ []) do
    time = Keyword.get(opts, :time, System.os_time(:second))
    since = Keyword.get(opts, :since)

    cond do
      NimbleTOTP.valid?(secret, code, time: time, since: since) ->
        unix_time_to_datetime(time)

      NimbleTOTP.valid?(secret, code, time: time - 30, since: since) ->
        unix_time_to_datetime(time - 30)

      true ->
        nil
    end
  end

  defp encrypt_mfa_secret(secret) do
    Phoenix.Token.encrypt(Endpoint, @mfa_secret_salt, secret, max_age: :infinity)
  end

  defp decrypt_mfa_secret(nil), do: :error

  defp decrypt_mfa_secret(secret) do
    Phoenix.Token.decrypt(Endpoint, @mfa_secret_salt, secret, max_age: :infinity)
  end

  defp generate_recovery_codes() do
    for _ <- 1..@mfa_recovery_code_count do
      code =
        5
        |> :crypto.strong_rand_bytes()
        |> Base.encode32(case: :upper, padding: false)
        |> binary_part(0, 8)

      String.slice(code, 0, 4) <> "-" <> String.slice(code, 4, 4)
    end
  end

  defp matching_recovery_code_index(recovery_code_hashes, code) do
    Enum.find_index(recovery_code_hashes, &Bcrypt.verify_pass(code, &1))
  end

  defp recovery_code_format?(code), do: String.match?(code, ~r/^[A-Z0-9]{4}-[A-Z0-9]{4}$/)

  defp consume_recovery_code(%User{} = user, code) do
    case matching_recovery_code_index(user.mfa_recovery_codes || [], code) do
      nil ->
        Repo.rollback(:invalid_code)

      recovery_code_index ->
        remaining_codes = List.delete_at(user.mfa_recovery_codes || [], recovery_code_index)

        user
        |> Changeset.change(%{mfa_recovery_codes: remaining_codes})
        |> Repo.update!()

        {:ok, :recovery_code}
    end
  end

  defp mark_mfa_used(%User{} = user, used_at) do
    user
    |> Changeset.change(%{mfa_last_used_at: used_at})
    |> Repo.update!()
  end

  defp unix_time_to_datetime(time) do
    {:ok, used_at} = DateTime.from_unix(time)
    DateTime.truncate(used_at, :second)
  end

  defp mfa_issuer() do
    "NervesHub #{Endpoint.url()}"
  end

  @doc ~S"""
  Delivers an email confirming that a users password has been updated.

  ## Examples

      iex> deliver_user_password_updated(user, &url(~p"/reset-password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_password_updated(%User{} = user, reset_url_fun) when is_function(reset_url_fun, 1) do
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

    case Repo.transact(multi) do
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
    end
  end

  def change_org_user_role(%OrgUser{} = ou, role) do
    ou
    |> Org.change_user_role(%{role: role})
    |> Repo.update()
  end

  def get_org_user!(%Scope{org: org}, %User{} = user) do
    get_org_user_query(org, user.id)
    |> Repo.one!()
  end

  def get_org_user!(%Scope{org: org}, user_id) do
    get_org_user_query(org, user_id)
    |> Repo.one!()
  end

  def get_org_user!(org, user) do
    get_org_user_query(org, user)
    |> Repo.one!()
  end

  def get_org_user(org, %User{id: id}) do
    get_org_user(org, id)
  end

  def get_org_user(org, user_id) do
    get_org_user_query(org, user_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      org_user -> {:ok, org_user}
    end
  end

  defp get_org_user_query(org, user_id) do
    OrgUser
    |> where([ou], ou.org_id == ^org.id)
    |> where([ou], ou.user_id == ^user_id)
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
    OrgUser
    |> where(org_id: ^org.id)
    |> where(user_id: ^user.id)
    |> where([ou], ou.role in ^User.role_or_higher(role))
    |> where([ou], is_nil(ou.deleted_at))
    |> Repo.exists?()
  end

  def get_user_orgs(%User{} = user) do
    from(
      o in Org,
      full_join: ou in OrgUser,
      on: ou.org_id == o.id,
      where: ou.user_id == ^user.id,
      where: is_nil(ou.deleted_at),
      group_by: o.id
    )
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

  def find_org_user_with_device_identifier(user, device_identifier) do
    OrgUser
    |> join(:left, [ou], o in assoc(ou, :org))
    |> join(:left, [ou, o], p in assoc(o, :products))
    |> join(:left, [ou, o, p], d in assoc(p, :devices))
    |> where([_, _, _, d], d.identifier == ^device_identifier)
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
  def authenticate(_, nil) do
    Bcrypt.no_user_verify()
    {:error, :authentication_failed}
  end

  def authenticate(email, password) do
    with {:ok, user} <- get_user_by_email(email),
         true <- is_binary(user.password_hash),
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
  def get_user_by_email_and_password(email, password) when is_binary(email) and is_binary(password) do
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
    User
    |> where(id: ^user_id)
    |> Repo.exclude_deleted()
    |> join(:left, [d], o in assoc(d, :orgs))
    |> join(:left, [d, o], p in assoc(o, :products))
    |> preload([d, o, p], orgs: {o, products: p})
    |> Repo.one!()
  end

  def get_orgs(%Scope{user: user}) do
    connected_org_devices_count =
      Device
      |> join(:inner, [d], lc in assoc(d, :latest_connection))
      |> join(:inner, [d], p in assoc(d, :product))
      |> where([_d, _dc, p], p.org_id == parent_as(:org).id)
      |> where([_d, dc], dc.status == :connected)
      |> select([d], %{count: count()})

    disconnected_org_devices_count =
      Device
      |> join(:left, [d], lc in assoc(d, :latest_connection))
      |> join(:inner, [d], p in assoc(d, :product))
      |> where([_d, _dc, p], p.org_id == parent_as(:org).id)
      |> where([_d, dc], is_nil(dc) or dc.status != :connected)
      |> select([d], %{count: count()})

    Org
    |> from(as: :org)
    |> Repo.exclude_deleted()
    |> join(:inner, [o], u in assoc(o, :users), on: u.id == ^user.id)
    |> join(:left, [o], p in subquery(products_subquery()), on: p.org_id == o.id)
    |> preload([d, o, p], products: p)
    |> select_merge([o], %{
      connected_devices_count: subquery(connected_org_devices_count),
      disconnected_devices_count: subquery(disconnected_org_devices_count)
    })
    |> Repo.all()
  end

  defp products_subquery() do
    connected_devices_count =
      Device
      |> join(:inner, [d], lc in assoc(d, :latest_connection))
      |> where([d], d.product_id == parent_as(:product).id)
      |> where([_d, dc], dc.status == :connected)
      |> select([d], %{count: count()})

    disconnected_devices_count =
      Device
      |> join(:left, [d], lc in assoc(d, :latest_connection))
      |> where([d], d.product_id == parent_as(:product).id)
      |> where([_d, dc], is_nil(dc) or dc.status != :connected)
      |> select([d], %{count: count()})

    Product
    |> from(as: :product)
    |> join(:left_lateral, [p], cdc in subquery(connected_devices_count), on: true, as: :connected_devices_count)
    |> join(:left_lateral, [p], ddc in subquery(disconnected_devices_count), on: true, as: :disconnected_devices_count)
    |> select_merge([_, connected_devices_count: cdc, disconnected_devices_count: ddc], %{
      connected_devices_count: cdc.count,
      disconnected_devices_count: ddc.count
    })
    |> Repo.exclude_deleted()
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

  @spec get_all_orgs() :: [Org.t()]
  def get_all_orgs() do
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

  def get_membership_by_org_name!(%Scope{} = current_scope, org_name) do
    OrgUser
    |> join(:left, [ou], u in assoc(ou, :user))
    |> join(:left, [ou], o in assoc(ou, :org))
    |> where([ou, _, _], is_nil(ou.deleted_at))
    |> where([_, _, o], is_nil(o.deleted_at))
    |> where([_, _, o], o.name == ^org_name)
    |> where([_, u], u.id == ^current_scope.user.id)
    |> preload([_, u, o], org: o, user: u)
    |> Repo.one!()
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

  @spec list_org_keys(Scope.t() | pos_integer(), boolean()) :: [OrgKey.t()]
  def list_org_keys(scope_or_org_id, load_created_by \\ true)

  def list_org_keys(%Scope{org: org}, load_created_by) do
    list_org_keys(org.id, load_created_by)
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

  def get_org_key(%Scope{org: org}, tk_id) do
    get_org_key_query(org.id, tk_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      key -> {:ok, key}
    end
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

  @spec invite(map(), Org.t(), User.t()) :: {:ok, Invite.t()} | {:error, Changeset.t()}
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

  @spec update_or_create_user_from_ueberauth(Ueberauth.Auth.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_or_create_user_from_ueberauth(%Ueberauth.Auth{info: info} = auth) do
    User
    |> where(email: ^info.email)
    |> Repo.exclude_deleted()
    |> Repo.one()
    |> case do
      nil ->
        {:ok, user} =
          %User{}
          |> User.oauth_changeset(auth)
          |> Repo.insert()

        {:ok, _} = UserNotifier.deliver_welcome_email(user)

        {:ok, user}

      %User{} = user ->
        user
        |> User.oauth_changeset(auth)
        |> Repo.update()
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

    Repo.transact(fn ->
      with {:ok, user} <- create_user(user_params),
           {:ok, user} <- add_org_user(org, user, %{role: invite.role}),
           {:ok, _invite} <- set_invite_accepted(invite) do
        {:ok, user}
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
  def create_user_session_token(%User{} = user, note \\ nil) do
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
  def create_user_api_token(%User{} = user, note) do
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
    |> Repo.transact()
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
  Delivers the reset password email to the given user, unless they have logged in with Google auth.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &url(~p"/password-reset/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(%User{google_id: google_id} = user, _reset_password_url_fun, login_url)
      when not is_nil(google_id) do
    UserNotifier.deliver_login_with_google_reminder(user, login_url)
  end

  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun, _login_url)
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
         true <- UserToken.token_still_valid?(:password_reset, token) do
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
    |> Repo.transact()
    |> case do
      {:ok, %{user: user}} ->
        _ = UserNotifier.deliver_reset_password_confirmation(user)

        {:ok, user}

      {:error, :user, changeset, _} ->
        {:error, changeset}
    end
  end

  def verify_cli_session_token(user, token) do
    with {:ok, cli_session} <- CLISessionCache.get(token),
         %{status: :waiting} <- cli_session,
         user_token = create_user_api_token(user, cli_session.note),
         cli_session = %{cli_session | status: :ready, user_id: user.id, user_token: user_token},
         :ok <- CLISessionCache.put(token, cli_session) do
      :ok
    else
      %{status: :ready, user_id: user_id} when user_id == user.id ->
        :ok

      %{status: :ready} ->
        {:error, :already_verified}

      _ ->
        {:error, :not_found}
    end
  end

  def generate_cli_session_token(note) do
    token = Ecto.UUID.generate()

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(5, :minute)
      |> DateTime.to_unix()

    with :error <- CLISessionCache.get(token),
         cli_session = %UserCLISession{
           token: token,
           status: :waiting,
           expires_at: expires_at,
           confirmation_code: Enum.random(100_000..999_999),
           note: note
         },
         :ok <- CLISessionCache.put(token, cli_session) do
      {:ok, cli_session}
    else
      _ ->
        {:error, :invalid_request}
    end
  end

  def cli_session_waiting?(user, token) do
    with {:ok, cli_session} <- CLISessionCache.get(token),
         %{status: status} when status in [:waiting, :ready] <- cli_session,
         %{user_id: user_id} when user_id in [user.id, nil] <- cli_session do
      {:ok, cli_session}
    else
      _ ->
        {:error, :invalid_request}
    end
  end

  def check_cli_session_ready(token) do
    with {:ok, cli_session} <- CLISessionCache.get(token),
         %{status: status} = cli_session when status == :ready <- cli_session,
         cli_session = %{cli_session | status: :verified},
         :ok <- CLISessionCache.put(token, cli_session) do
      {:ok, cli_session}
    else
      %{status: :waiting} = cli_session ->
        {:ok, cli_session}

      _ ->
        {:error, :not_found}
    end
  end
end
