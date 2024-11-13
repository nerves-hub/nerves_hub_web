defmodule NervesHub.Features.DeviceProductFeature do
  use Ecto.Schema

  alias NervesHub.Devices.Device
  alias NervesHub.Features.ProductFeature

  schema "device_product_features" do
    belongs_to(:device, Device)
    belongs_to(:product_feature, ProductFeature)

    field(:allowed, :boolean, default: false)
  end

  def changeset(device_product_feature \\ %__MODULE__{}, attrs) do
    device_product_feature
    |> Ecto.Changeset.cast(attrs, [:device_id, :product_feature_id, :allowed])
    |> Ecto.Changeset.validate_required([:device_id, :product_feature_id, :allowed])
  end
end
