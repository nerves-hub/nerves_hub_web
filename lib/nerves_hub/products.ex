defmodule NervesHub.Products do
  @moduledoc """
  The Products context.
  """

  import Ecto.Query, warn: false

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.Scope
  alias NervesHub.Accounts.User
  alias NervesHub.Devices.Device
  alias NervesHub.Extensions
  alias NervesHub.Products.CustomHealthMetricsLabel
  alias NervesHub.Products.Product
  alias NervesHub.Products.SharedSecretAuth
  alias NervesHub.Repo

  @export_certs_sep "\n\n"

  def get_by_name!(%Scope{} = current_scope, product_name) do
    Product
    |> join(:left, [p], o in assoc(p, :org))
    |> join(:left, [p, o], ou in assoc(o, :org_users))
    |> where([p], is_nil(p.deleted_at))
    |> where([_, o], is_nil(o.deleted_at))
    |> where([_, _, ou], is_nil(ou.deleted_at))
    |> where([p], p.name == ^product_name)
    |> where([_, o], o.id == ^current_scope.org.id)
    |> where([_, _, ou], ou.user_id == ^current_scope.user.id)
    |> Repo.one!()
  end

  @spec get_products(Scope.t()) :: [Product.t()]
  def get_products(%Scope{user: user, org: org}, opts \\ []) do
    from(
      p in Product,
      as: :product,
      full_join: ou in OrgUser,
      on: p.org_id == ou.org_id,
      where:
        p.org_id == ^org.id and ou.user_id == ^user.id and
          ou.role in ^User.role_or_higher(:view),
      group_by: p.id
    )
    |> add_connected_devices_count(opts[:with_counts])
    |> add_disconnected_devices_count(opts[:with_counts])
    |> Repo.exclude_deleted()
    |> Repo.all()
  end

  defp add_connected_devices_count(query, true) do
    connected_devices_count =
      Device
      |> join(:inner, [d], lc in assoc(d, :latest_connection))
      |> where([d], d.product_id == parent_as(:product).id)
      |> where([_d, dc], dc.status == :connected)
      |> select([d], count())

    select_merge(query, %{connected_devices_count: subquery(connected_devices_count)})
  end

  defp add_connected_devices_count(query, _) do
    query
  end

  defp add_disconnected_devices_count(query, true) do
    disconnected_devices_count =
      Device
      |> join(:left, [d], lc in assoc(d, :latest_connection))
      |> where([d], d.product_id == parent_as(:product).id)
      |> where([_d, dc], is_nil(dc) or dc.status != :connected)
      |> select([d], count())

    select_merge(query, %{disconnected_devices_count: subquery(disconnected_devices_count)})
  end

  defp add_disconnected_devices_count(query, _) do
    query
  end

  @spec get_products_by_user_and_org(User.t(), Org.t()) :: [Product.t()]
  def get_products_by_user_and_org(%User{id: user_id}, %Org{id: org_id}) do
    query =
      from(
        p in Product,
        full_join: ou in OrgUser,
        on: p.org_id == ou.org_id,
        where:
          p.org_id == ^org_id and ou.user_id == ^user_id and
            ou.role in ^User.role_or_higher(:view),
        group_by: p.id
      )

    query
    |> Repo.exclude_deleted()
    |> Repo.all()
  end

  @doc """
  Gets a single product.

  Raises `Ecto.NoResultsError` if the Product does not exist.

  ## Examples

      iex> get_product!(123)
      %Product{}

      iex> get_product!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_product!(pos_integer()) :: Product.t()
  def get_product!(id) do
    Product
    |> Repo.exclude_deleted()
    |> Repo.get!(id)
  end

  @spec get_product(pos_integer()) :: {:ok, Product.t()} | {:error, :not_found}
  def get_product(id) do
    Product
    |> Repo.exclude_deleted()
    |> Repo.get(id)
    |> case do
      nil -> {:error, :not_found}
      product -> {:ok, product}
    end
  end

  @spec get_product_by_name!(Scope.t(), String.t()) :: Product.t()
  def get_product_by_name!(%Scope{org: org}, name) do
    get_product_by_org_id_and_name_query(org.id, name)
    |> Repo.one!()
  end

  @spec get_product_by_org_id_and_name!(pos_integer(), String.t()) :: Product.t()
  def get_product_by_org_id_and_name!(org_id, name) do
    get_product_by_org_id_and_name_query(org_id, name)
    |> Repo.one!()
  end

  @spec get_product_by_org_id_and_name(pos_integer(), String.t()) ::
          {:ok, Product.t()} | {:error, :not_found}
  def get_product_by_org_id_and_name(org_id, name) do
    get_product_by_org_id_and_name_query(org_id, name)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      product -> {:ok, product}
    end
  end

  def get_product_by_org_id_and_name_query(org_id, name) do
    Product
    |> where(org_id: ^org_id, name: ^name)
    |> Repo.exclude_deleted()
  end

  @doc """
  Gets a single product that a user has access to.

  If the product is not found or the user does not have access, returns `{:error, :not_found}`.
  """
  @spec get_by_id(Scope.t(), pos_integer) :: {:ok, Product.t()} | {:error, :not_found}
  def get_by_id(%Scope{user: user}, id) do
    Product
    |> join(:inner, [p], o in assoc(p, :org))
    |> join(:inner, [_, o], ou in assoc(o, :org_users))
    |> where([p], is_nil(p.deleted_at))
    |> where([_, o], is_nil(o.deleted_at))
    |> where(id: ^id)
    |> where([_, _, ou], ou.user_id == ^user.id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      product -> {:ok, product}
    end
  end

  @doc """
  Creates a product.
  """
  @spec create_product(map()) :: {:ok, Product.t()} | {:error, Ecto.Changeset.t()}
  def create_product(params) do
    Product.changeset(%Product{}, params)
    |> Repo.insert()
  end

  @doc """
  Deletes a Product.

  ## Examples

      iex> delete_product(product)
      {:ok, %Product{}}

      iex> delete_product(product)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_product(Product.t()) :: {:ok, Product.t()} | {:error, Ecto.Changeset.t()}
  def delete_product(%Product{} = product) do
    product
    |> Product.delete_changeset()
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking product changes.

  ## Examples

      iex> change_product(product)
      %Ecto.Changeset{source: %Product{}}

  """
  @spec change_product(Product.t()) :: Ecto.Changeset.t()
  def change_product(%Product{} = product) do
    Product.changeset(product, %{})
  end

  @spec get_shared_secret_auth(pos_integer(), pos_integer()) ::
          {:ok, SharedSecretAuth.t()} | {:error, :not_found}
  def get_shared_secret_auth(product_id, auth_id) do
    SharedSecretAuth
    |> join(:inner, [ssa], p in assoc(ssa, :product))
    |> where([ssa], ssa.id == ^auth_id)
    |> where([_, p], p.id == ^product_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      auth -> {:ok, auth}
    end
  end

  @spec get_shared_secret_auth(String.t()) :: {:ok, SharedSecretAuth.t()} | {:error, :not_found}
  def get_shared_secret_auth(key) do
    SharedSecretAuth
    |> join(:inner, [ssa], p in assoc(ssa, :product))
    |> where([ssa], ssa.key == ^key)
    |> where([ssa], is_nil(ssa.deactivated_at))
    |> where([_, p], is_nil(p.deleted_at))
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      auth -> {:ok, auth}
    end
  end

  @spec load_shared_secret_auth(Product.t()) :: Product.t()
  def load_shared_secret_auth(product) do
    product
    |> Ecto.reset_fields([:shared_secret_auths])
    |> Repo.preload(:shared_secret_auths)
    |> case do
      %Product{} = reloaded -> reloaded
      _ -> raise "Product not found"
    end
  end

  @spec create_shared_secret_auth(Product.t()) ::
          {:ok, SharedSecretAuth.t()} | {:error, Ecto.Changeset.t()}
  def create_shared_secret_auth(product) do
    product
    |> SharedSecretAuth.create_changeset()
    |> Repo.insert()
  end

  @spec deactivate_shared_secret_auth(Product.t(), pos_integer()) ::
          {:ok, SharedSecretAuth.t()} | {:error, Ecto.Changeset.t()}
  def deactivate_shared_secret_auth(product, shared_secret_id) do
    {:ok, auth} = get_shared_secret_auth(product.id, shared_secret_id)

    auth
    |> SharedSecretAuth.deactivate_changeset()
    |> Repo.update()
  end

  @spec devices_export_reducer(Product.t(), any(), fun()) :: any()
  def devices_export_reducer(%Product{} = product, acc, callback) do
    product = Repo.preload(product, [:org])

    Repo.transact(
      fn ->
        Device
        |> select([d, dc], [:id, :identifier, :description, :tags, :deleted_at, :product_id])
        |> where([d], d.product_id == ^product.id)
        |> Repo.exclude_deleted()
        |> Repo.stream(max_rows: 500)
        |> Stream.chunk_every(100)
        |> Stream.flat_map(&Repo.preload(&1, :device_certificates))
        |> Stream.map(&device_csv_line(&1, product))
        |> Enum.reduce_while(acc, fn line, acc ->
          callback.(acc, line)
          |> case do
            {:ok, acc} ->
              {:cont, acc}

            {:error, _} ->
              {:halt, acc}
          end
        end)
        |> then(fn res -> {:ok, res} end)
      end,
      timeout: 90_000
    )
  end

  defp device_csv_line(device, product) do
    [
      device.identifier,
      device.description,
      "#{Enum.join(device.tags || [], ",")}",
      product.name,
      product.org.name,
      format_device_certificates(device)
    ]
  end

  defp format_device_certificates(device) do
    for db_cert <- device.device_certificates, into: "" do
      if db_cert.der do
        db_cert.der
        |> X509.Certificate.from_der!()
        |> X509.Certificate.to_pem()
      else
        %{
          serial: db_cert.serial,
          aki: Base.encode16(db_cert.aki),
          ski: if(db_cert.ski, do: Base.encode16(db_cert.ski)),
          not_before: db_cert.not_before,
          not_after: db_cert.not_after
        }
        |> Jason.encode!()
        |> Kernel.<>(@export_certs_sep)
      end
    end
  end

  def enable_extension_setting(%Product{} = product, extension_string) do
    product = get_product!(product.id)

    Product.changeset(product, %{"extensions" => %{extension_string => true}})
    |> Repo.update()
    |> tap(fn
      {:ok, _} ->
        Extensions.broadcast_extension_event(product, "attach", extension_string)

      _ ->
        :nope
    end)
  end

  def disable_extension_setting(%Product{} = product, extension_string) do
    product = get_product!(product.id)

    Product.changeset(product, %{"extensions" => %{extension_string => false}})
    |> Repo.update()
    |> tap(fn
      {:ok, _} ->
        Extensions.broadcast_extension_event(product, "detach", extension_string)

      _ ->
        :nope
    end)
  end

  @doc """
  Returns the product's custom health metric labels as a `%{key => label}` map.
  """
  @spec custom_health_metrics_labels(Product.t()) :: %{optional(String.t()) => String.t()}
  def custom_health_metrics_labels(%Product{id: product_id}) do
    CustomHealthMetricsLabel
    |> where(product_id: ^product_id)
    |> select([l], {l.key, l.label})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Sets the custom label for a health metric key on a product.

  Inserts a new label or updates the existing one for the `{product, key}` pair.
  A blank label removes any existing custom label, reverting to the default.
  """
  @spec set_custom_health_metrics_label(Product.t(), String.t(), String.t()) ::
          {:ok, CustomHealthMetricsLabel.t() | nil} | {:error, Ecto.Changeset.t()}
  def set_custom_health_metrics_label(%Product{} = product, key, label) do
    if blank?(label) do
      delete_custom_health_metrics_label(product, key)
      {:ok, nil}
    else
      %CustomHealthMetricsLabel{}
      |> CustomHealthMetricsLabel.changeset(%{
        product_id: product.id,
        key: key,
        label: String.trim(label)
      })
      |> Repo.insert(
        on_conflict: {:replace, [:label, :updated_at]},
        conflict_target: [:product_id, :key]
      )
    end
  end

  @doc """
  Removes the custom label for a health metric key on a product.
  """
  @spec delete_custom_health_metrics_label(Product.t(), String.t()) :: :ok
  def delete_custom_health_metrics_label(%Product{id: product_id}, key) do
    CustomHealthMetricsLabel
    |> where(product_id: ^product_id, key: ^key)
    |> Repo.delete_all()

    :ok
  end

  defp blank?(value), do: is_nil(value) or String.trim(value) == ""
end
