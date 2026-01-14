defmodule NervesHub.Scripts do
  import Ecto.Query

  alias Ecto.Changeset
  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs.ProductTemplates
  alias NervesHub.Filtering, as: CommonFiltering
  alias NervesHub.Products
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias NervesHub.Scripts.Script

  @spec filter(Product.t(), map()) :: {[Product.t()], Flop.Meta.t()}
  def filter(product, opts \\ %{}) do
    Script
    |> from()
    |> CommonFiltering.filter(
      product,
      opts
    )
  end

  def all_by_product(product) do
    Script
    |> where([c], c.product_id == ^product.id)
    |> order_by(:name)
    |> Repo.all()
  end

  def get!(id) do
    Repo.get!(Script, id)
  end

  def get_by_product_and_id!(product, id) do
    Repo.get_by!(Script, id: id, product_id: product.id)
  end

  def get(product, id) do
    case Repo.get_by(Script, id: id, product_id: product.id) do
      nil ->
        {:error, :not_found}

      command ->
        {:ok, command}
    end
  end

  def get_by_product_and_name(product, name) do
    case Repo.get_by(Script, name: name, product_id: product.id) do
      nil ->
        {:error, :not_found}

      script ->
        {:ok, script}
    end
  end

  def get_by_product_and_name_with_id_fallback(product, name_or_id) do
    # Try to find by name first
    case get_by_product_and_name(product, name_or_id) do
      {:ok, script} ->
        {:ok, script}

      {:error, :not_found} ->
        # If not found by name, try by ID
        case Integer.parse(name_or_id) do
          {id, ""} -> get(product, id)
          _ -> {:error, :not_found}
        end
    end
  end

  @spec create(Product.t(), User.t(), map()) :: {:ok, Script.t()} | {:error, Changeset.t()}
  def create(product, user, params) do
    Script.create_changeset(product, user, params)
    |> Repo.insert()
    |> case do
      {:ok, script} ->
        ProductTemplates.audit_script_created(user, product, script)
        {:ok, script}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @spec update(Script.t(), User.t(), map()) :: {:ok, Script.t()} | {:error, Changeset.t()}
  def update(script, user, params) do
    script
    |> Script.update_changeset(user, params)
    |> Repo.update()
    |> case do
      {:ok, script} ->
        product = Products.get_product!(script.product_id)

        ProductTemplates.audit_script_updated(user, product, script)

        {:ok, script}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @spec delete(non_neg_integer(), Product.t(), User.t()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def delete(id, product, user) do
    get_by_product_and_id!(product, id)
    |> Repo.delete()
    |> case do
      {:ok, script} ->
        ProductTemplates.audit_script_deleted(user, product, script)

        {:ok, script}

      err ->
        err
    end
  end
end
