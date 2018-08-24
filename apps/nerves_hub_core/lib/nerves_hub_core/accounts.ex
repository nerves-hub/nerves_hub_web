defmodule NervesHubCore.Accounts do
  import Ecto.Query
  alias Ecto.Changeset
  alias Ecto.UUID
  alias NervesHubCore.Accounts.{Org, User, UserCertificate, Invite, OrgKey}
  alias NervesHubCore.Repo
  alias Comeonin.Bcrypt

  @spec create_org(map) ::
          {:ok, Org.t()}
          | {:error, Changeset.t()}
  def create_org(params) do
    %Org{}
    |> Org.changeset(params)
    |> Repo.insert()
  end

  def change_user(user, params \\ %{})

  def change_user(%User{id: nil} = user, params) do
    User.creation_changeset(user, params)
  end

  def change_user(%User{} = user, params) do
    User.update_changeset(user, params)
  end

  def create_user(params) do
    %User{}
    |> change_user(params)
    |> Repo.insert()
  end

  @spec create_user_certificate(User.t(), map) ::
          {:ok, User.t()}
          | {:error, Changeset.t()}
  def create_user_certificate(%User{} = user, params) do
    user
    |> Ecto.build_assoc(:user_certificates)
    |> UserCertificate.changeset(params)
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
    user = Repo.get_by(User, email: email) |> User.with_default_org() |> User.with_org_keys()

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

  @spec get_user(integer()) ::
          {:ok, User.t()}
          | {:error, :not_found}
  def get_user(user_id) do
    query = from(u in User, where: u.id == ^user_id)

    query
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  def get_user_with_all_orgs(user_id) do
    query = from(u in User, where: u.id == ^user_id) |> User.with_all_orgs()

    query
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  def get_user_by_email(email) do
    query = from(u in User, where: u.email == ^email)

    query
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @spec get_user_certificates(User.t()) ::
          {:ok, [UserCertificate.t()]}
          | {:error, :not_found}
  def get_user_certificates(%User{id: user_id}) do
    query = from(uc in UserCertificate, where: uc.user_id == ^user_id)

    query
    |> Repo.all()
  end

  @spec get_user_certificate(User.t(), integer()) ::
          {:ok, UserCertificate.t()}
          | {:error, :not_found}
  def get_user_certificate(%User{id: user_id}, cert_id) do
    query = from(uc in UserCertificate, where: uc.user_id == ^user_id, where: uc.id == ^cert_id)

    query
    |> Repo.one()
  end

  @spec delete_user_certificate(UserCertificate.t()) ::
          {:ok, UserCertificate.t()}
          | {:error, Changeset.t()}
  def delete_user_certificate(%UserCertificate{} = cert) do
    Repo.delete(cert)
  end

  def get_user_by_certificate_serial(serial) do
    query =
      from(
        uc in UserCertificate,
        where: uc.serial == ^serial,
        preload: [:user]
      )

    query
    |> Repo.one()
    |> case do
      nil -> nil
      %{user: user} -> user |> User.with_default_org()
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

  @spec get_org(integer()) ::
          {:ok, Org.t()}
          | {:error, :not_found}
  def get_org(id) do
    Org
    |> Repo.get(id)
    |> case do
      nil -> {:error, :not_found}
      org -> {:ok, org}
    end
  end

  def get_org_with_org_keys(id) do
    Org
    |> Repo.get(id)
    |> case do
      nil -> {:error, :not_found}
      org -> {:ok, org |> Org.with_org_keys()}
    end
  end

  def get_org_by_name_and_user(org_name, %User{id: user_id}) do
    query =
      from(
        o in Org,
        join: u in assoc(o, :users),
        where: u.id == ^user_id and o.name == ^org_name
      )

    Repo.one(query)
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
    |> Org.changeset(attrs)
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
    Repo.delete(org_key)
  end

  def change_org_key(org_key, params \\ %{})

  def change_org_key(%OrgKey{id: nil} = org_key, params) do
    OrgKey.changeset(org_key, params)
  end

  def change_org_key(%OrgKey{id: _id} = org_key, params) do
    OrgKey.update_changeset(org_key, params)
  end

  @spec invite(%{name: String.t(), email: String.t()}, Org.t()) ::
          {:ok, Invite.t()}
          | {:error, Changeset.t()}
  def invite(params, org) do
    params = Map.merge(params, %{"org_id" => org.id, "token" => Ecto.UUID.generate()})

    %Invite{}
    |> Invite.changeset(params)
    |> Repo.insert()
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

  @spec create_user_from_invite(Invite.t(), Org.t(), map) ::
          {:ok, User.t()}
          | {:error}
  def create_user_from_invite(invite, org, user_params) do
    user_params =
      %{email: invite.email, name: invite.name}
      |> Enum.into(user_params)

    Repo.transaction(fn ->
      with {:ok, user} <- create_user(%{orgs: [org]} |> Enum.into(user_params)),
           {:ok, _invite} <- set_invite_accepted(invite) do
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
    |> change_user(user_params)
    |> Repo.update()
  end

  def add_user_to_org(%User{} = user, %Org{} = org) do
    all_orgs = user |> User.with_all_orgs() |> Map.get(:orgs, [])
    params = %{orgs: [org | all_orgs]}

    user
    |> User.update_orgs_changeset(params)
    |> Repo.update()
  end

  def remove_user_from_org(%User{} = user, %Org{} = org) do
    all_orgs = user |> User.with_all_orgs() |> Map.get(:orgs, [])

    {_, remaining_orgs} = Enum.split_with(all_orgs, fn x -> x.id == org.id end)
    params = %{orgs: remaining_orgs}

    user
    |> User.update_orgs_changeset(params)
    |> Repo.update()
  end

  defp set_invite_accepted(invite) do
    invite
    |> Invite.changeset(%{accepted: true})
    |> Repo.update()
  end

  @spec update_password_reset_token(String.t()) :: :ok
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

  @spec reset_password(String.t(), map) ::
          {:ok, User.t()}
          | {:error, :not_found}
  def reset_password(reset_password_token, params) do
    reset_password_token
    |> get_user_with_password_reset_token()
    |> case do
      {:ok, user} ->
        user
        |> User.password_changeset(params)
        |> Repo.update()

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end
end
