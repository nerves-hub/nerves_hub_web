defmodule NervesHubCore.Devices.Device do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias NervesHubCore.Accounts.Tenant
  alias NervesHubCore.Firmwares.Firmware

  alias __MODULE__

  @type t :: %__MODULE__{}
  @optional_params [
    :last_known_firmware_id,
    :last_communication,
    :description,
    :tags
  ]
  @required_params [:tenant_id, :identifier]

  schema "devices" do
    belongs_to(:tenant, Tenant)
    belongs_to(:last_known_firmware, Firmware)

    field(:identifier, :string)
    field(:description, :string)
    field(:last_communication, :utc_datetime)
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

  def with_firmware(device_query) do
    device_query
    |> preload(:last_known_firmware)
  end

  def with_tenant(device_query) do
    device_query
    |> preload(:tenant)
  end
end
