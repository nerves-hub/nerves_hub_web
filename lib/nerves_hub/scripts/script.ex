defmodule NervesHub.Scripts.Script do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.User
  alias NervesHub.Products.Product

  @type t :: %__MODULE__{}
  @required [:name, :text]

  schema "scripts" do
    belongs_to(:product, Product)
    belongs_to(:created_by, User, where: [deleted_at: nil])
    belongs_to(:last_updated_by, User, where: [deleted_at: nil])

    field(:name, :string)
    field(:text, :string)

    timestamps()
  end

  def create_changeset(struct, params) do
    struct
    |> cast(params, @required ++ [:created_by_id])
    |> validate_required(@required ++ [:created_by_id])
    |> validate_length(:name, lte: 255)
    |> foreign_key_constraint(:created_by_id)
  end

  def update_changeset(struct, params) do
    struct
    |> cast(params, @required ++ [:last_updated_by_id])
    |> validate_required(@required ++ [:last_updated_by_id])
    |> validate_length(:name, lte: 255)
    |> foreign_key_constraint(:last_updated_by_id)
  end
end
