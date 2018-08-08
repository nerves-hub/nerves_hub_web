defmodule NervesHubCore.Products do
  @moduledoc """
  The Products context.
  """

  import Ecto.Query, warn: false
  alias NervesHubCore.Repo

  alias NervesHubCore.Products.Product
  alias NervesHubCore.Accounts.Tenant

  @doc """
  Returns the list of products.

  ## Examples

      iex> list_products()
      [%Product{}, ...]

  """
  def list_products_by_tenant(%Tenant{id: tenant_id}) do
    from(
      p in Product,
      where: p.tenant_id == ^tenant_id,
      order_by: [desc: p.id]
    )
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
  def get_product!(id), do: Repo.get!(Product, id)

  def get_product_with_tenant(%Tenant{} = tenant, id) do
    Product
    |> Repo.get_by(id: id, tenant_id: tenant.id)
    |> case do
      nil -> {:error, :not_found}
      product -> {:ok, product}
    end
  end

  def get_product_by_tenant_id_and_name(tenant_id, name) do
    Product
    |> Repo.get_by(tenant_id: tenant_id, name: name)
    |> case do
      nil -> {:error, :not_found}
      product -> {:ok, product}
    end
  end

  @doc """
  Creates a product.

  ## Examples

      iex> create_product(%{field: value})
      {:ok, %Product{}}

      iex> create_product(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_product(attrs \\ %{}) do
    %Product{}
    |> Product.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a product.

  ## Examples

      iex> update_product(product, %{field: new_value})
      {:ok, %Product{}}

      iex> update_product(product, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_product(%Product{} = product, attrs) do
    product
    |> Product.changeset(attrs)
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
  def delete_product(%Product{} = product) do
    Repo.delete(product)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking product changes.

  ## Examples

      iex> change_product(product)
      %Ecto.Changeset{source: %Product{}}

  """
  def change_product(%Product{} = product) do
    Product.changeset(product, %{})
  end
end
