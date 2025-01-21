defmodule NervesHub.Scripts do
  import Ecto.Query

  alias NervesHub.Products.Product
  alias NervesHub.Scripts.Script

  alias NervesHub.Repo

  @spec filter(Product.t(), map()) ::
          {:ok, {[Product.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def filter(product_id, opts \\ %{}) do
    opts = Map.reject(opts, fn {_key, val} -> is_nil(val) end)

    sort = Map.get(opts, :sort, "name")
    sort_direction = Map.get(opts, :sort_direction, "desc")

    sort_opts = {String.to_existing_atom(sort_direction), String.to_atom(sort)}

    flop = %Flop{
      page: String.to_integer(Map.get(opts, :page, "1")),
      page_size: String.to_integer(Map.get(opts, :page_size, "25"))
    }

    Script
    |> where([f], f.product_id == ^product_id)
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

  def create(product, params) do
    product
    |> Ecto.build_assoc(:scripts)
    |> Script.changeset(params)
    |> Repo.insert()
  end

  def update(command, params) do
    command
    |> Script.changeset(params)
    |> Repo.update()
  end
end
