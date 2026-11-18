defmodule NervesHub.Products.ApiKeys do
  @moduledoc """
  Context for product API keys.

  See `NervesHub.Products.ApiKey` for what a key is and how it differs from a
  user API token.
  """

  import Ecto.Query

  alias NervesHub.Accounts.OrgRole
  alias NervesHub.Accounts.OrgRoles
  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs.ProductTemplates
  alias NervesHub.Products.ApiKey
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias Phoenix.Channel.Server, as: ChannelServer

  # Recording every use would be a write on every request an automated client
  # makes. "Last used" only needs to be good enough to tell whether a key is
  # still in use before deactivating it.
  @last_used_resolution_seconds 60

  @doc """
  A product's keys, active ones first, newest first within each group.
  """
  @spec list(Product.t()) :: [ApiKey.t()]
  def list(%Product{id: product_id}) do
    ApiKey
    |> where(product_id: ^product_id)
    |> order_by([k], asc_nulls_first: k.deactivated_at, desc: k.inserted_at, desc: k.id)
    |> preload([:created_by, :org_role])
    |> Repo.all()
  end

  @doc """
  Create a key for a product.

  Returns the key's record along with the key itself, which is not stored and
  can't be recovered once this returns.
  """
  @spec create(Product.t(), User.t(), map()) ::
          {:ok, ApiKey.t(), String.t()} | {:error, Ecto.Changeset.t()}
  def create(%Product{} = product, %User{} = user, attrs) do
    {token, changeset} = ApiKey.create_changeset(product, user, attrs)

    Repo.transact(fn ->
      with {:ok, api_key} <- Repo.insert(OrgRoles.validate_org_role(changeset)) do
        api_key = Repo.preload(api_key, [:created_by, :org_role])
        :ok = ProductTemplates.audit_api_key_created(user, product, api_key)
        {:ok, api_key}
      end
    end)
    |> case do
      {:ok, api_key} -> {:ok, api_key, token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Stop a product's key from authenticating.

  API requests authenticate on every call, so they stop at once. A socket only
  authenticates when it connects, so any socket still open with the key is
  disconnected (see `socket_id/1`).

  Deactivating a key that is already deactivated leaves it as it was.
  """
  @spec deactivate(Product.t(), User.t(), pos_integer() | String.t()) ::
          {:ok, ApiKey.t()} | {:error, :not_found}
  def deactivate(%Product{} = product, %User{} = user, id) do
    Repo.transact(fn ->
      case get(product, id) do
        {:ok, %ApiKey{deactivated_at: nil} = api_key} ->
          {:ok, api_key} = Repo.update(ApiKey.deactivate_changeset(api_key))
          :ok = ProductTemplates.audit_api_key_deactivated(user, product, api_key)
          {:ok, api_key}

        other ->
          other
      end
    end)
    |> case do
      {:ok, api_key} ->
        # After the commit, so a client that reconnects straight away finds the
        # key already deactivated.
        :ok = ChannelServer.broadcast(NervesHub.PubSub, socket_id(api_key), "disconnect", %{})
        {:ok, api_key}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  The id of any socket opened with a key, which `deactivate/3` disconnects.
  """
  @spec socket_id(ApiKey.t()) :: String.t()
  def socket_id(%ApiKey{id: id}), do: "product_api_key:#{id}"

  @doc """
  The active key a token belongs to, with everything its scope is built from
  loaded: its product, that product's organization, and its custom role if it
  has one.

  A key stops authenticating when it is deactivated, or when its product or
  organization is deleted.
  """
  @spec authenticate(String.t()) :: {:ok, ApiKey.t()} | :error
  def authenticate(token) when is_binary(token) do
    with {:ok, token_hash} <- ApiKey.hash_token(token),
         %ApiKey{} = api_key <- Repo.one(active_key_query(token_hash)) do
      {:ok, mark_used(api_key)}
    else
      _ -> :error
    end
  end

  @doc """
  Whether any active key holds `org_role`.

  Deleting a role a key holds would quietly change what that automation can
  do, so `NervesHub.Accounts.OrgRoles.delete_org_role/1` refuses while one
  does.
  """
  @spec any_with_org_role?(OrgRole.t()) :: boolean()
  def any_with_org_role?(%OrgRole{id: id}) do
    ApiKey
    |> where(org_role_id: ^id)
    |> where([k], is_nil(k.deactivated_at))
    |> join(:inner, [k], p in assoc(k, :product))
    |> where([_, p], is_nil(p.deleted_at))
    |> Repo.exists?()
  end

  @doc """
  How many active keys hold each role in the product's organization, keyed the
  way `NervesHub.Accounts.OrgRoles.member_counts/1` keys members: by built-in
  role, and by custom role id.
  """
  @spec key_counts(Product.t()) :: %{(atom() | integer()) => non_neg_integer()}
  def key_counts(%Product{org_id: org_id}) do
    ApiKey
    |> where(org_id: ^org_id)
    |> where([k], is_nil(k.deactivated_at))
    |> group_by([k], [k.role, k.org_role_id])
    |> select([k], {k.role, k.org_role_id, count()})
    |> Repo.all()
    |> Map.new(fn {role, org_role_id, count} -> {org_role_id || role, count} end)
  end

  defp get(product, id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> get(product, id)
      _ -> {:error, :not_found}
    end
  end

  defp get(%Product{id: product_id}, id) when is_integer(id) do
    ApiKey
    |> where(product_id: ^product_id, id: ^id)
    |> Repo.fetch()
  end

  defp active_key_query(token_hash) do
    ApiKey
    |> join(:inner, [k], p in assoc(k, :product))
    |> join(:inner, [_, p], o in assoc(p, :org))
    |> where([k], k.token_hash == ^token_hash)
    |> where([k], is_nil(k.deactivated_at))
    |> where([_, p, o], is_nil(p.deleted_at) and is_nil(o.deleted_at))
    |> preload([_, p, o], product: {p, org: o})
    |> preload(:org_role)
  end

  defp mark_used(%ApiKey{last_used_at: last_used_at} = api_key) do
    now = DateTime.utc_now(:second)

    if is_nil(last_used_at) or DateTime.diff(now, last_used_at) >= @last_used_resolution_seconds do
      _ = Repo.update_all(where(ApiKey, id: ^api_key.id), set: [last_used_at: now])
      %{api_key | last_used_at: now}
    else
      api_key
    end
  end
end
