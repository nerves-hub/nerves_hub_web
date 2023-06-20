defmodule NervesHub.Devices.Device do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query
  import EctoEnum

  alias NervesHub.Accounts.Org
  alias NervesHub.Devices.DeviceCertificate
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Firmwares.FirmwareMetadata
  alias NervesHub.Products.Product

  alias __MODULE__

  @type t :: %__MODULE__{}
  @optional_params [
    :last_communication,
    :description,
    :updates_enabled,
    :tags,
    :deleted_at,
    :update_attempts,
    :updates_blocked_until,
    :connection_types,
    :connecting_code,
    :deployment_id
  ]
  @required_params [:org_id, :product_id, :identifier]

  defenum(ConnectionType, :connection_type, [:cellular, :ethernet, :wifi])

  schema "devices" do
    belongs_to(:org, Org, where: [deleted_at: nil])
    belongs_to(:product, Product, where: [deleted_at: nil])
    belongs_to(:deployment, Deployment)
    embeds_one(:firmware_metadata, FirmwareMetadata, on_replace: :update)
    has_many(:device_certificates, DeviceCertificate, on_delete: :delete_all)

    field(:identifier, :string)
    field(:description, :string)
    field(:last_communication, :utc_datetime)
    field(:updates_enabled, :boolean, default: true)
    field(:tags, NervesHub.Types.Tag)
    field(:deleted_at, :utc_datetime)
    field(:update_attempts, {:array, :utc_datetime}, default: [])
    field(:updates_blocked_until, :utc_datetime)
    field(:connection_types, {:array, ConnectionType})
    field(:connecting_code, :string)

    timestamps()
  end

  def changeset(%Device{} = device, params) do
    device
    |> cast(params, @required_params ++ @optional_params)
    |> cast_embed(:firmware_metadata)
    |> validate_required(@required_params)
    |> validate_length(:tags, min: 1)
    |> unique_constraint(:identifier, name: :devices_org_id_identifier_index)
  end

  def with_org(device_query) do
    device_query
    |> preload(:org)
  end
end
