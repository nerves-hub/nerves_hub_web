defmodule NervesHub.Devices.UpdateStat do
  use Ecto.Schema

  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Products.Product

  import Ecto.Changeset

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

  @spec create_changeset(Device.t(), DeploymentGroup.t() | nil, map()) :: Ecto.Changeset.t()
  def create_changeset(device, nil, params) do
    params =
      params
      |> Map.put(:device_id, device.id)
      |> Map.put(:product_id, device.product_id)

    %__MODULE__{}
    |> cast(params, @required ++ @optional)
    |> cast_assoc(:device)
    |> cast_assoc(:product)
    |> validate_required(@required)
  end

  def create_changeset(device, deployment_group, params) do
    params =
      params
      |> Map.put(:device_id, device.id)
      |> Map.put(:product_id, device.product_id)
      |> Map.put(:deployment_id, deployment_group.id)

    %__MODULE__{}
    |> cast(params, @required ++ @optional)
    |> cast_assoc(:device)
    |> cast_assoc(:product)
    |> cast_assoc(:deployment)
    |> validate_required(@required)
  end
end
