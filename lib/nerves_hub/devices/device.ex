defmodule NervesHub.Devices.Device do
  use Ecto.Schema

  import Ecto.Changeset

  alias __MODULE__
  alias NervesHub.Accounts.Org
  alias NervesHub.Devices.ComponentTopology
  alias NervesHub.Devices.DeviceCertificate
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.DeviceFirmware
  alias NervesHub.Devices.DeviceHealth
  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Devices.NetworkIdentity
  alias NervesHub.Devices.UpdateStat
  alias NervesHub.Extensions.DeviceExtensionsSetting
  alias NervesHub.Firmwares.FirmwareMetadata
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Products.Product
  alias NervesHub.Types.Tag

  @derive {Flop.Schema, filterable: [], sortable: []}

  @type t :: %__MODULE__{}

  @type firmware_validation_statuses :: :validated | :not_validated | :unknown

  @type update_mode :: :off | :automatic | :device_managed

  @optional_params [
    :description,
    :update_mode,
    :managed_updates_allowed,
    :tags,
    :deleted_at,
    :update_attempts,
    :updates_blocked_until,
    :connecting_code,
    :deployment_id,
    :current_device_firmware_id,
    :status,
    :firmware_validation_status,
    :firmware_auto_revert_detected,
    :first_seen_at,
    :custom_location_coordinates
  ]
  @required_params [:org_id, :product_id, :identifier]

  @derive {Phoenix.Param, key: :identifier}
  schema "devices" do
    belongs_to(:org, Org)
    belongs_to(:product, Product)
    belongs_to(:deployment_group, DeploymentGroup, foreign_key: :deployment_id)
    belongs_to(:latest_health, DeviceHealth)
    belongs_to(:current_device_firmware, DeviceFirmware, type: UUIDv7)

    has_one(:latest_connection, DeviceConnection)
    has_one(:inflight_update, InflightUpdate)
    has_one(:component_topology, ComponentTopology, on_delete: :delete_all)

    has_many(:device_certificates, DeviceCertificate, on_delete: :delete_all)
    has_many(:device_connections, DeviceConnection, on_delete: :delete_all)
    has_many(:device_metrics, DeviceMetric, on_delete: :delete_all)
    has_many(:device_health, DeviceHealth, on_delete: :delete_all)
    has_many(:network_identities, NetworkIdentity, on_delete: :delete_all)
    has_many(:update_stats, UpdateStat, on_delete: :delete_all)

    field(:identifier, :string)
    field(:description, :string)
    field(:tags, Tag)
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

    field(:firmware_validation_status, Ecto.Enum,
      values: [:validated, :not_validated, :unknown],
      default: :unknown
    )

    field(:firmware_auto_revert_detected, :boolean, default: false)

    field(:update_mode, Ecto.Enum,
      values: [:off, :automatic, :device_managed],
      default: :automatic
    )

    # Whether the device may put *itself* into :device_managed. An operator setting
    # that mode from the dashboard is always allowed; this gates the device only.
    field(:managed_updates_allowed, :boolean, default: false)

    # To be removed in a migration in the next release, replaced by :update_mode
    field(:updates_enabled, :boolean, default: true)
    field(:update_attempts, {:array, :utc_datetime}, default: [])
    field(:updates_blocked_until, :utc_datetime)

    # To be removed in a migration in the next release
    # field(:priority_updates, :boolean, default: false)
    # field(:network_interface, Ecto.Enum, values: [:wifi, :ethernet, :cellular, :unknown])

    field(:deleted_at, :utc_datetime)

    timestamps()
  end

  def changeset(%Device{} = device, params) do
    device
    |> cast(params, @required_params ++ @optional_params)
    |> cast_embed(:firmware_metadata)
    |> cast_embed(:extensions)
    |> validate_required(@required_params)
    |> unique_constraint(:identifier)
    |> then(fn changeset ->
      if device.deleted_at && !Map.has_key?(changeset.changes, :deleted_at) do
        add_error(changeset, :deleted_at, "cannot update while marked as deleted")
      else
        changeset
      end
    end)
  end

  def update_deployment_group(device, deployment_group) do
    device
    |> change()
    |> put_change(:deployment_id, deployment_group.id)
  end

  def clear_deployment_group(device) do
    device
    |> change()
    |> put_change(:deployment_id, nil)
  end

  @doc """
  Whether the device takes firmware updates at all.

  Retains the meaning the `updates_enabled` boolean had before `update_mode`
  replaced it, and is what the JSON API still reports under that name. A
  `:device_managed` device has updates enabled — it asks for them rather than
  being pushed them.
  """
  @spec updates_enabled?(t()) :: boolean()
  def updates_enabled?(%Device{update_mode: update_mode}), do: update_mode != :off

  @doc """
  Whether the deployment orchestrator may push firmware to this device.

  False for both `:off` and `:device_managed`, for different reasons: the first
  is frozen, the second asks for its own updates.
  """
  @spec orchestrator_may_push?(t()) :: boolean()
  def orchestrator_may_push?(%Device{update_mode: update_mode}), do: update_mode == :automatic

  def clear_updates_information_changeset(%Device{} = device) do
    device
    |> change()
    |> put_change(:update_attempts, [])
    |> put_change(:updates_blocked_until, nil)
  end

  def firmware_validated(%Device{} = device) do
    device
    |> change()
    |> put_change(:firmware_validation_status, :validated)
  end
end
