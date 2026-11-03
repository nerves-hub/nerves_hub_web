defmodule NervesHubWeb.MaintenanceEndpoint do
  @moduledoc """
  The only endpoint a node runs when `MAINTENANCE_MODE` is set.

  It has no sockets, so a device or an open dashboard trying to connect gets the
  same 503 as everything else, and tries again later. Nothing here can need
  Postgres or ClickHouse: neither is connected in this mode.
  """

  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :nerves_hub

  alias NervesHubWeb.Plugs.ImAlive
  alias NervesHubWeb.Plugs.Maintenance

  # Without this, a load balancer would take the node out of rotation for failing
  # its health check, and nobody would ever see the page.
  plug(ImAlive, check_database: false)

  plug(Plug.Static, at: "/", from: :nerves_hub, gzip: false, only: ~w(favicon.ico))

  plug(Sentry.PlugContext)

  plug(Maintenance)
end
