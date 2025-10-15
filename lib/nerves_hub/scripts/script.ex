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

  def validate_changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, @required ++ @optional)
    |> validate_required(@required)
    |> validate_length(:name, lte: 255)
  end

  def create_changeset(product, created_by, params) do
    validate_changeset(params)
    |> put_assoc(:product, product)
    |> foreign_key_constraint(:product_id)
    |> put_assoc(:created_by, created_by)
    |> foreign_key_constraint(:created_by_id)
  end

  def update_changeset(%__MODULE__{} = struct, edited_by, params \\ %{}) do
    struct
    |> validate_changeset(params)
    |> put_change(:last_updated_by_id, edited_by.id)
    |> foreign_key_constraint(:last_updated_by_id)
  end
end
