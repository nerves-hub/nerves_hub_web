defmodule NervesHub.Commands.Command do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Products.Product

  schema "commands" do
    belongs_to(:product, Product)

    field(:name, :string)
    field(:text, :string)

    timestamps()
  end

  def create_changeset(struct, params) do
    struct
    |> cast(params, [:name, :text])
    |> validate_required([:name, :text])
    |> validate_length(:name, lte: 255)
    |> validate_change(:text, fn :text, text ->
      if String.contains?(text, "\n") do
        [text: "cannot contain newlines"]
      else
        []
      end
    end)
  end

  def update_changeset(struct, params) do
    create_changeset(struct, params)
  end
end

defmodule NervesHub.Commands do
  import Ecto.Query

  alias NervesHub.Commands.Command
  alias NervesHub.Repo

  def all_by_product(product) do
    Command
    |> where([c], c.product_id == ^product.id)
    |> order_by(:name)
    |> Repo.all()
  end

  def get!(id) do
    Repo.get!(Command, id)
  end

  def get(product, id) do
    case Repo.get_by(Command, id: id, product_id: product.id) do
      nil ->
        {:error, :not_found}

      command ->
        {:ok, command}
    end
  end

  def create(product, params) do
    product
    |> Ecto.build_assoc(:commands)
    |> Command.create_changeset(params)
    |> Repo.insert()
  end

  def update(command, params) do
    command
    |> Command.update_changeset(params)
    |> Repo.update()
  end
end
