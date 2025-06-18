defmodule NervesHub.Workers.RemoveDeviceFromPenaltyBox do
  @moduledoc """
  Removes a device from the penalty box by clearing its `updates_blocked_until`
  and `update_attempts` fields.
  """
  use Oban.Worker, max_attempts: 1

  require Logger

  alias NervesHub.Devices

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"device_id" => device_id}}) do
    device = Devices.get_device(device_id)

    case device do
      nil ->
        :ok

      device ->
        Logger.info("Device #{device.identifier} taken out of penalty box")

        Devices.update_device(device, %{updates_blocked_until: nil, update_attempts: []})
    end
  end
end
