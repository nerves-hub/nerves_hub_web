defmodule NervesHub.Devices.UpdateStat do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Products.Product

  @type t :: %__MODULE__{}

  @required [
    :device_id,
    :product_id,
    :type,
    :target_firmware_uuid,
    :update_bytes,
    :saved_bytes
  ]
  @optional [
    :source_firmware_uuid,
    :deployment_id
  ]

  @primary_key false
  schema "update_stats" do
    belongs_to(:product, Product)
    belongs_to(:device, Device)
    belongs_to(:deployment, DeploymentGroup)

    field(:type, :string)
    field(:source_firmware_uuid, Ecto.UUID)
    field(:target_firmware_uuid, Ecto.UUID)
    field(:update_bytes, :integer, default: 0)
    field(:saved_bytes, :integer, default: 0)

    timestamps()
  end

  @spec create_changeset(Device.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(device, params) do
    params =
      params
      |> Map.put(:device_id, device.id)
      |> Map.put(:product_id, device.product_id)

    %__MODULE__{}
    |> cast(params, @required ++ @optional)
    |> validate_required(@required)
  end
end
