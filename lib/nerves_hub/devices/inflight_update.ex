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
      values: [
        :requested,
        :rescheduled,
        :ignored,
        :received,
        :started,
        :downloading,
        :updating,
        :completed,
        :failed,
        :expired
      ],
      default: :requested
    )

    field(:progress, :integer)

    timestamps()
  end

  # The statuses in which a device is still occupied by an update.
  #
  # `:completed` is one of them. It means the device finished writing the
  # firmware, not that it is running it: the row lives on until the device
  # reboots and rejoins, which is where `NervesHub.DeviceLink` clears it. Until
  # then the device is still taking up one of the deployment's slots, and
  # offering it another update would be offering one to a device that is on its
  # way down.
  #
  # The rest are outcomes, and each deletes its row as it is written. `:failed`
  # speaks for itself, `:expired` is the update timing out, `:ignored` is the
  # device declining it, and `:rescheduled` is the device asking for it later;
  # the last two also put it in the penalty box.
  #
  # A row only exists while one of these holds, because reaching an outcome
  # deletes it. Saying so explicitly means the queries no longer depend on that
  # being true, which is what a history of updates would change.
  @active_statuses [:requested, :received, :started, :downloading, :updating, :completed]

  @doc """
  The statuses in which a device is still occupied by an update.
  """
  @spec active_statuses() :: [:requested | :received | :started | :downloading | :updating | :completed, ...]
  def active_statuses(), do: @active_statuses

  def empty_requested_changeset(device_id) do
    %InflightUpdate{}
    |> change(%{device_id: device_id})
    |> validate_required([:device_id])
    |> unique_constraint(:device_id, name: :inflight_updates_device_id_index)
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

  def update_status_changeset(inflight_update, status, progress) do
    cast(inflight_update, %{status: status, progress: progress}, [:status, :progress])
  end
end
