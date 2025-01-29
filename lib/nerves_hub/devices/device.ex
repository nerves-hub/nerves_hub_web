defmodule NervesHub.Devices.Device do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.Org
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Devices.DeviceCertificate
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.Extensions.DeviceExtensionsSetting
  alias NervesHub.Firmwares.FirmwareMetadata
  alias NervesHub.Products.Product

  alias __MODULE__

  @derive {Flop.Schema, filterable: [], sortable: []}

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
    :status,
    :first_seen_at,
    :custom_location_coordinates
  ]
  @required_params [:org_id, :product_id, :identifier]

  schema "devices" do
    belongs_to(:org, Org)
    belongs_to(:product, Product)
    belongs_to(:deployment, Deployment)
    belongs_to(:latest_connection, DeviceConnection, type: :binary_id)

    has_many(:device_certificates, DeviceCertificate, on_delete: :delete_all)
    has_many(:device_connections, DeviceConnection, on_delete: :delete_all)
    has_many(:device_metrics, DeviceMetric, on_delete: :delete_all)

    field(:identifier, :string)
    field(:description, :string)
    field(:tags, NervesHub.Types.Tag)
    field(:connecting_code, :string)
    field(:custom_location_coordinates, {:array, :float})

    embeds_one(:extensions, DeviceExtensionsSetting,
      defaults_to_struct: true,
      on_replace: :update
    )

    field(:first_seen_at, :utc_datetime)

    field(:status, Ecto.Enum,
      values: [:registered, :provisioned],
      default: :registered
    )

    embeds_one(:firmware_metadata, FirmwareMetadata, on_replace: :update)

    field(:updates_enabled, :boolean, default: true)
    field(:update_attempts, {:array, :utc_datetime}, default: [])
    field(:updates_blocked_until, :utc_datetime)

    field(:deleted_at, :utc_datetime)

    timestamps()

    # Deprecated fields, remove these on or after the 5th of Jan 2025.
    # Also remove index from NervesHub.Repo.Migrations.AddConnectionStatusIndexToDevices.
    # field(:connection_status, Ecto.Enum,
    #   values: [:connected, :disconnected, :not_seen],
    #   default: :not_seen
    # )
    # field(:connection_established_at, :utc_datetime)
    # field(:connection_disconnected_at, :utc_datetime)
    # field(:connection_last_seen_at, :utc_datetime)
    # field(:connection_metadata, :map, default: %{})
    # field(:connection_types, {:array, Ecto.Enum}, values: [:cellular, :ethernet, :wifi])
  end

  def changeset(%Device{} = device, params) do
    device
    |> cast(params, @required_params ++ @optional_params)
    |> cast_embed(:firmware_metadata)
    |> cast_embed(:extensions)
    |> validate_required(@required_params)
    |> validate_length(:tags, min: 1)
    |> unique_constraint(:identifier)
  end
end
