defmodule NervesHub.Devices.InflightUpdate do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments.DeploymentGroup

  @type t :: %__MODULE__{}

  schema "inflight_updates" do
    belongs_to(:device, Device)
    belongs_to(:deployment_group, DeploymentGroup, foreign_key: :deployment_id)
    belongs_to(:firmware, Firmware)

    field(:firmware_uuid, Ecto.UUID)
    field(:priority_queue, :boolean, default: false)

    field(:status, Ecto.Enum,
      values: [:requested, :received, :started, :downloading, :updating, :completed, :expired],
      default: :requested
    )

    field(:progress, :integer)

    timestamps()
  end

  def manual_requested_changeset(device_id, firmware) do
    %InflightUpdate{}
    |> change(%{
      device_id: device_id,
      firmware_id: firmware.id,
      firmware_uuid: firmware.uuid
    })
    |> validate_required([:device_id, :firmware_id, :firmware_uuid])
    |> unique_constraint(:device_id, name: :inflight_updates_device_id_index)
  end

  def deployment_requested_changeset(deployment_group, device_id, priority_queue) do
    %InflightUpdate{}
    |> change(%{
      device_id: device_id,
      deployment_id: deployment_group.id,
      firmware_id: deployment_group.current_release.firmware_id,
      firmware_uuid: deployment_group.current_release.firmware.uuid,
      priority_queue: priority_queue
    })
    |> validate_required([:device_id, :deployment_id, :firmware_id, :firmware_uuid])
    |> unique_constraint(:device_id, name: :inflight_updates_device_id_index)
  end
end
