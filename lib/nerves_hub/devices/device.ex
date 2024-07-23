defmodule NervesHub.Devices.Device do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.Org
  alias NervesHub.Devices.DeviceCertificate
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Firmwares.FirmwareMetadata
  alias NervesHub.Products.Product

  alias __MODULE__

  @type t :: %__MODULE__{}
  @optional_params [
    :description,
    :updates_enabled,
    :tags,
    :deleted_at,
    :update_attempts,
    :updates_blocked_until,
    :connecting_code,
    :deployment_id,
    :connection_status,
    :connection_established_at,
    :connection_disconnected_at,
    :connection_last_seen_at,
    :connection_types,
    :connection_metadata
  ]
  @required_params [:org_id, :product_id, :identifier]

  schema "devices" do
    belongs_to(:org, Org, where: [deleted_at: nil])
    belongs_to(:product, Product, where: [deleted_at: nil])
    belongs_to(:deployment, Deployment)
    embeds_one(:firmware_metadata, FirmwareMetadata, on_replace: :update)
    has_many(:device_certificates, DeviceCertificate, on_delete: :delete_all)

    field(:identifier, :string)
    field(:description, :string)
    field(:updates_enabled, :boolean, default: true)
    field(:tags, NervesHub.Types.Tag)
    field(:deleted_at, :utc_datetime)
    field(:update_attempts, {:array, :utc_datetime}, default: [])
    field(:updates_blocked_until, :utc_datetime)

    field(:connection_status, Ecto.Enum,
      values: [:connected, :disconnected, :not_seen],
      default: :not_seen
    )

    field(:connection_established_at, :utc_datetime)
    field(:connection_disconnected_at, :utc_datetime)
    field(:connection_last_seen_at, :utc_datetime)
    field(:connection_types, {:array, Ecto.Enum}, values: [:cellular, :ethernet, :wifi])
    field(:connecting_code, :string)
    field(:connection_metadata, :map, default: %{})

    timestamps()
  end

  def changeset(%Device{} = device, params) do
    device
    |> cast(params, @required_params ++ @optional_params)
    |> cast_embed(:firmware_metadata)
    |> validate_required(@required_params)
    |> validate_length(:tags, min: 1)
    |> unique_constraint(:identifier)
  end
end
