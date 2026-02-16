defmodule NervesHub.Products do
  @moduledoc """
  The Products context.
  """

  import Ecto.Query, warn: false

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.User
  alias NervesHub.Devices.Device
  alias NervesHub.Extensions
  alias NervesHub.Products.Product
  alias NervesHub.Products.SharedSecretAuth
  alias NervesHub.Repo
  alias NervesHub.Uploads
  alias NimbleCSV.RFC4180, as: CSV

  @csv_certs_sep "\n\n"
  @csv_header ["identifier", "description", "tags", "product", "org", "certificates"]

  def __csv_header__(), do: @csv_header

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

  @spec update_product_banner(Product.t(), String.t()) ::
          {:ok, Product.t()} | {:error, any()}
  def update_product_banner(%Product{} = product, file_path) do
    ext = Path.extname(file_path)
    key = "products/#{product.id}/banner#{ext}"
    old_key = product.banner_upload_key

    with :ok <- Uploads.upload(file_path, key),
         {:ok, product} <-
           product
           |> Product.banner_changeset(%{banner_upload_key: key})
           |> Repo.update() do
      if old_key && old_key != key do
        Uploads.delete(old_key)
      end

      {:ok, product}
    end
  end

  @spec remove_product_banner(Product.t()) :: {:ok, Product.t()} | {:error, any()}
  def remove_product_banner(%Product{banner_upload_key: nil} = product), do: {:ok, product}

  def remove_product_banner(%Product{} = product) do
    old_key = product.banner_upload_key

    case product
         |> Product.banner_changeset(%{banner_upload_key: nil})
         |> Repo.update() do
      {:ok, product} ->
        Uploads.delete(old_key)
        {:ok, product}

      error ->
        error
    end
  end

  @spec banner_url(Product.t()) :: String.t() | nil
  def banner_url(%Product{banner_upload_key: nil}), do: nil

  def banner_url(%Product{banner_upload_key: key}) do
    ts = System.unique_integer()
    "#{Uploads.url(key)}?v=#{ts}"
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

  @spec devices_csv(Product.t()) :: binary()
  def devices_csv(%Product{} = product) do
    product = Repo.preload(product, [:org])

    {:ok, devices} =
      Repo.transact(fn ->
        devices =
          Device
          |> where([d], d.product_id == ^product.id)
          |> Repo.exclude_deleted()
          |> Repo.stream(max_rows: 100)
          |> Stream.chunk_every(100)
          |> Stream.flat_map(&Repo.preload(&1, :device_certificates))
          |> Stream.map(&device_csv_line(&1, product))
          |> Enum.to_list()

        {:ok, devices}
      end)

    [@csv_header | devices]
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
end
