defmodule NervesHubCore.Products.Product do
  use Ecto.Schema
  import Ecto.Changeset

  alias NervesHubCore.Accounts.Tenant
  alias NervesHubCore.Firmwares.Firmware

  @required_params [:name, :tenant_id]
  @optional_params []

  schema "products" do
    has_many(:firmwares, Firmware)

    belongs_to(:tenant, Tenant)

    field(:name, :string)

    timestamps()
  end

  @doc false
  def changeset(product, attrs) do
    product
    |> cast(attrs, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> unique_constraint(:name, name: :products_tenant_id_name_index)
  end
end
