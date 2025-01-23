defmodule NervesHub.Workers.CleanStaleDeviceConnections do
  use Oban.Worker,
    max_attempts: 5,
    queue: :device

  alias NervesHub.Devices.Connections

  @impl Oban.Worker
  def perform(_) do
    _ = Connections.clean_stale_connections()

    :ok
  end
end
