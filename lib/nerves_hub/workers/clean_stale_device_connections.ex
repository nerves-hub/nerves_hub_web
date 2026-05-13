defmodule NervesHub.Workers.CleanStaleDeviceConnections do
  use Oban.Worker,
    queue: :cleanup,
    max_attempts: 5,
    unique: [states: [:available, :scheduled, :executing]]

  alias NervesHub.Devices.Connections

  @impl Oban.Worker
  def perform(_) do
    _ = Connections.clean_stale_connections()

    :ok
  end
end
