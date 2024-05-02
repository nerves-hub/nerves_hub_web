defmodule NervesHub.Scripts do
  import Ecto.Query

  alias NervesHub.Scripts.Script
  alias NervesHub.Repo

  def all_by_product(product) do
    Script
    |> where([c], c.product_id == ^product.id)
    |> order_by(:name)
    |> Repo.all()
  end

  def get!(id) do
    Repo.get!(Script, id)
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
    |> Script.create_changeset(params)
    |> Repo.insert()
  end

  def update(command, params) do
    command
    |> Script.update_changeset(params)
    |> Repo.update()
  end
end
