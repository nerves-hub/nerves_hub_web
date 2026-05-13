defmodule NervesHub.Devices.DeviceFirmware do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareMetadata

  @validation_statuses [:validated, :not_validated, :unknown]

  @type t :: %__MODULE__{}
  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "device_firmwares" do
    belongs_to(:device, Device)

    belongs_to(:firmware, Firmware)

    embeds_one(:firmware_metadata, FirmwareMetadata, on_replace: :update)
    field(:firmware_validation_status, Ecto.Enum, values: @validation_statuses, default: :unknown)
    field(:firmware_auto_revert_detected, :boolean, default: false)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def create_changeset(device, firmware_metadata, validation_status, revert_detected?) do
    params = %{
      device_id: device.id,
      firmware_metadata: firmware_metadata,
      firmware_validation_status: validation_status,
      firmware_auto_revert_detected: revert_detected?
    }

    %__MODULE__{}
    |> cast(params, [:device_id, :firmware_validation_status, :firmware_auto_revert_detected])
    |> cast_embed(:firmware_metadata)
    |> prepare_changes(fn changeset ->
      Firmwares.get_firmware_by_product_id_and_uuid(device.product_id, get_in(firmware_metadata.uuid))
      |> case do
        {:ok, firmware} -> put_change(changeset, :firmware_id, firmware.id)
        {:error, _} -> changeset
      end
    end)
  end

  def firmware_validated(device) do
    %__MODULE__{id: device.current_device_firmware_id}
    |> change()
    |> put_change(:firmware_validation_status, :validated)
  end
end
