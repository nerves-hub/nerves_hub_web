defmodule NervesHub.Scripts do
  import Ecto.Query

  alias Ecto.Changeset
  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs.ProductTemplates
  alias NervesHub.Products
  alias NervesHub.Products.Product
  alias NervesHub.Scripts.Script

  alias NervesHub.Repo

  @spec filter(Product.t(), map()) :: {[Product.t()], Flop.Meta.t()}
  def filter(product, opts \\ %{}) do
    opts = Map.reject(opts, fn {_key, val} -> is_nil(val) end)

    sort = Map.get(opts, :sort, "name")
    sort_direction = Map.get(opts, :sort_direction, "desc")

    sort_opts = {String.to_existing_atom(sort_direction), String.to_atom(sort)}

    flop = %Flop{
      page: String.to_integer(Map.get(opts, :page, "1")),
      page_size: String.to_integer(Map.get(opts, :page_size, "25"))
    }

    Script
    |> where([f], f.product_id == ^product.id)
    |> order_by(^sort_opts)
    |> Flop.run(flop)
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

  @spec create(Product.t(), User.t(), map()) :: {:ok, Script.t()} | {:error, Changeset.t()}
  def create(product, user, params) do
    product
    |> Ecto.build_assoc(:scripts)
    |> Script.changeset(params)
    |> Repo.insert()
    |> case do
      {:ok, script} ->
        ProductTemplates.audit_script_created(user, product, script)
        {:ok, script}

      err ->
        err
    end
  end

  @spec update(Script.t(), User.t(), map()) :: {:ok, Script.t()} | {:error, Changeset.t()}
  def update(script, user, params) do
    script
    |> Script.changeset(params)
    |> Repo.update()
    |> case do
      {:ok, script} ->
        product = Products.get_product!(script.product_id)

        ProductTemplates.audit_script_updated(user, product, script)

        {:ok, script}

      err ->
        err
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
