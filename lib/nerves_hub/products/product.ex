defmodule NervesHub.Products.Product do
  use Ecto.Schema
  import Ecto.Changeset

  alias NervesHub.Accounts.Tenant
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Devices.Device
  alias NervesHub.Deployments.Deployment

  @required_params [:name, :tenant_id]
  @optional_params []

  schema "products" do
    has_many(:devices, Device)
    has_many(:deployments, Deployment)
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
  end
end
