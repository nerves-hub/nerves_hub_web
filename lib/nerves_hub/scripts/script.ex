defmodule NervesHub.Scripts.Script do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.User
  alias NervesHub.Products.Product
  alias NervesHub.Types.Tag

  @type t :: %__MODULE__{}
  @required [:name, :text]
  @optional [:tags]

  schema "scripts" do
    belongs_to(:product, Product)
    belongs_to(:created_by, User, where: [deleted_at: nil])
    belongs_to(:last_updated_by, User, where: [deleted_at: nil])

    field(:name, :string)
    field(:text, :string)
    field(:tags, Tag)

    timestamps()
  end

  def create_changeset(%__MODULE__{} = struct, product, created_by, params) do
    struct
    |> cast(params, @required ++ @optional)
    |> put_assoc(:product, product)
    |> put_assoc(:created_by, created_by)
    |> validate_required(@required ++ [:created_by])
    |> validate_length(:name, lte: 255)
    |> foreign_key_constraint(:created_by_id)
  end

  def update_changeset(%__MODULE__{} = struct, edited_by, params \\ %{}) do
    struct
    |> cast(params, @required ++ @optional)
    |> put_change(:last_updated_by_id, edited_by.id)
    |> validate_required(@required)
    |> validate_length(:name, lte: 255)
    |> foreign_key_constraint(:last_updated_by_id)
  end
end
