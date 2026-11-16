defmodule NervesHub.Workers.CleanStaleDeviceConnectionHistory do
  @moduledoc """
  Closes connections ClickHouse still thinks are open, once an hour.

  A safety net, not the main sweep. `CleanStaleDeviceConnections` runs every
  minute against Postgres and writes a disconnected history row for every
  connection it marks stale, so ClickHouse is normally already up to date.
  What this catches is a disconnect row that never reached ClickHouse, such as
  one still in `NervesHub.Analytics.Buffer` when its node died.

  It runs hourly because finding those rows is a `FINAL` scan of all of
  `device_connection_history`, which costs the same however few rows are left,
  and a lost row staying open for up to an hour is harmless. See
  `NervesHub.Devices.Connections.clean_stale_connections_from_analytics/0`.
  """

  use Oban.Worker,
    queue: :cleanup,
    max_attempts: 5,
    unique: [states: [:available, :scheduled, :executing, :suspended, :retryable]]

  alias NervesHub.Devices.Connections

  @impl Oban.Worker
  def perform(_) do
    :ok = Connections.clean_stale_connections_from_analytics()
  end
end
