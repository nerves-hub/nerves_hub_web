defmodule NervesHubCore.Accounts.Tenant do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHubCore.Accounts.{User, TenantKey}
  alias NervesHubCore.Firmwares.Firmware
  alias NervesHubCore.Devices.Device
  alias NervesHubCore.Products.Product
  alias __MODULE__

  @type t :: %__MODULE__{}

  schema "tenants" do
    has_many(:users, User)
    has_many(:tenant_keys, TenantKey)
    has_many(:products, Product)
    has_many(:devices, Device)

    field(:name, :string)

    timestamps()
  end

  def changeset(%Tenant{} = tenant, params) do
    tenant
    |> cast(params, [:name])
    |> validate_required([:name])
  end
end
