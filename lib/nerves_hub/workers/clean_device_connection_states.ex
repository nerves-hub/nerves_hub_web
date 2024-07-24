defmodule NervesHub.Workers.CleanDeviceConnectionStates do
  use Oban.Worker,
    max_attempts: 5,
    queue: :device

  @impl true
  def perform(_) do
    NervesHub.Devices.clean_connection_states()

    :ok
  end
end
