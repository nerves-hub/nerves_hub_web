defmodule NervesHub.Scripts.Script do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Products.Product

  schema "scripts" do
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
  end

  def update_changeset(struct, params) do
    create_changeset(struct, params)
  end
end
