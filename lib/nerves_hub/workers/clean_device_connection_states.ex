defmodule NervesHub.Workers.CleanDeviceConnectionStates do
  use Oban.Worker,
    max_attempts: 5,
    queue: :device

  alias NervesHub.Devices
  alias NervesHub.Devices.Connections

  @impl true
  def perform(_) do
    Devices.clean_connection_states()
    Connections.clean_stale_connections()

    :ok
  end
end
