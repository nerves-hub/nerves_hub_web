defmodule NervesHub.Devices.Device do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias NervesHub.Accounts.Tenant
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Firmwares.Firmware

  alias __MODULE__

  @type t :: %__MODULE__{}
  @optional_params [
    :target_deployment_id,
    :current_firmware_id,
    :last_communication,
    :description,
    :product,
    :tags
  ]
  @required_params [:tenant_id, :identifier, :architecture, :platform]

  schema "devices" do
    belongs_to(:tenant, Tenant)
    belongs_to(:target_deployment, Deployment)
    belongs_to(:current_firmware, Firmware)

    field(:identifier, :string)
    field(:description, :string)
    field(:product, :string)
    field(:platform, :string)
    field(:last_communication, :utc_datetime)
    field(:architecture, :string)
    field(:tags, {:array, :string})

    timestamps()
  end

  def changeset(%Device{} = device, params) do
    device
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> validate_length(:tags, min: 1)
    |> unique_constraint(:identifier, name: :devices_tenant_id_identifier_index)
  end

  def with_deployment(device_query) do
    device_query
    |> preload(:target_deployment)
  end

  def with_tenant(device_query) do
    device_query
    |> preload(:tenant)
  end
end
