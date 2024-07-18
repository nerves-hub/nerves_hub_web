defmodule NervesHub.Products do
  @moduledoc """
  The Products context.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias NervesHub.Repo

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Products.Product
  alias NervesHub.Products.SharedSecretAuth
  alias NervesHub.Accounts.User

  alias NimbleCSV.RFC4180, as: CSV

  @csv_certs_sep "\n\n"
  @csv_header ["identifier", "description", "tags", "product", "org", "certificates"]

  def __csv_header__, do: @csv_header

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
  Creates a product.
  """
  @spec create_product(map()) :: {:ok, Product.t()} | {:error, Ecto.Changeset.t()}
  def create_product(params) do
    multi =
      Multi.new()
      |> Multi.insert(:product, Product.changeset(%Product{}, params))

    case Repo.transaction(multi) do
      {:ok, result} ->
        {:ok, result.product}

      {:error, :product, changeset, _} ->
        {:error, changeset}
    end
  end

  @doc """
  Updates a product.

  ## Examples

      iex> update_product(product, %{field: new_value})
      {:ok, %Product{}}

      iex> update_product(product, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_product(Product.t(), map()) :: {:ok, Product.t()} | {:error, Ecto.Changeset.t()}
  def update_product(%Product{} = product, attrs) do
    product
    |> Product.update_changeset(attrs)
    |> Repo.update()
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

  @spec devices_csv(Product.t()) :: binary()
  def devices_csv(%Product{} = product) do
    product = Repo.preload(product, [:org, devices: :device_certificates])
    data = Enum.map(product.devices, &device_csv_line(&1, product))

    [@csv_header | data]
    |> CSV.dump_to_iodata()
    |> IO.iodata_to_binary()
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
        |> Kernel.<>(@csv_certs_sep)
      end
    end
  end
end
