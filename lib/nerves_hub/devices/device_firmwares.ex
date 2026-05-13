defmodule NervesHub.Devices.DeviceFirmwares do
  import Ecto.Query

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceFirmware
  alias NervesHub.Repo

  @spec add_reported_firmware(Device.t(), map(), any(), boolean()) :: :ok | {:ok, DeviceFirmware.t()}
  def add_or_update_reported_firmware(device, firmware_metadata, validation_status, revert_detected)

  def add_or_update_reported_firmware(
        %{current_device_firmware_id: nil} = device,
        firmware_metadata,
        validation_status,
        revert_detected
      ) do
    {:ok, _} = add_reported_firmware(device, firmware_metadata, validation_status, revert_detected)
  end

  def add_or_update_reported_firmware(device, _firmware_metadata, validation_status, revert_detected) do
    :ok = update_reported_information(device, validation_status, revert_detected)
  end

  @spec add_reported_firmware(Device.t(), map(), any(), boolean()) ::
          {:ok, DeviceFirmware.t()} | {:error, Ecto.Changeset.t()}
  def add_reported_firmware(device, firmware_metadata, validation_status, revert_detected) do
    device
    |> DeviceFirmware.create_changeset(firmware_metadata, validation_status, revert_detected)
    |> Repo.insert()
  end

  @spec update_reported_information(Device.t(), any(), boolean()) :: :ok | :error
  def update_reported_information(device, validation_status, revert_detected) do
    DeviceFirmware
    |> where(id: ^device.current_device_firmware_id)
    |> Repo.update_all(
      set: [
        firmware_validation_status: validation_status,
        firmware_auto_revert_detected: revert_detected
      ]
    )
    |> case do
      {1, _} -> :ok
      _ -> :error
    end
  end

  @spec paginate(Device.t(), any()) :: {[any()], Flop.Meta.t()}
  def paginate(device, opts) do
    flop = %Flop{page: opts.page, page_size: opts.page_size}

    DeviceFirmware
    |> where(device_id: ^device.id)
    |> order_by(desc: :inserted_at)
    |> Flop.run(flop)
  end
end
