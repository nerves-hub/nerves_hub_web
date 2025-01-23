defmodule NervesHub.Workers.DeleteOldDeviceConnections do
  use Oban.Worker,
    max_attempts: 5,
    queue: :device

  alias NervesHub.Devices.Connections

  @impl Oban.Worker
  def perform(_) do
    _ = Connections.delete_old_connections()

    :ok
  end
end
