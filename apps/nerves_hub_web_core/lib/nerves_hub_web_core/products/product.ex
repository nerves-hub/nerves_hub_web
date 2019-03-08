defmodule NervesHubWebCore.Products.Product do
  use Ecto.Schema
  import Ecto.Changeset

  alias NervesHubWebCore.Accounts.Org
  alias NervesHubWebCore.Firmwares.Firmware
  alias NervesHubWebCore.Products.ProductUser

  @required_params [:name, :org_id]
  @optional_params []

  schema "products" do
    has_many(:firmwares, Firmware)
    has_many(:product_users, ProductUser)
    has_many(:users, through: [:product_users, :user])

    belongs_to(:org, Org)

    field(:name, :string)

    timestamps()
  end

  @doc false
  def changeset(product, attrs) do
    product
    |> cast(attrs, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> unique_constraint(:name, name: :products_org_id_name_index)
  end
end
