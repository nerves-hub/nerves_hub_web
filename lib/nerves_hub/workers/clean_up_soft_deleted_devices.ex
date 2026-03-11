defmodule NervesHub.Workers.CleanUpSoftDeletedDevices do
  use Oban.Worker,
    max_attempts: 5,
    queue: :device

  alias NervesHub.Devices

  @impl Oban.Worker
  def perform(_) do
    if Application.get_env(:nerves_hub, :clean_up_soft_deleted_devices, false) do
      _ = Devices.clean_up_soft_deleted_devices()
    end

    :ok
  end
end
