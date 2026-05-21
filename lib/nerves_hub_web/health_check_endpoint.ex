defmodule NervesHubWeb.HealthCheckEndpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :nerves_hub

  alias NervesHubWeb.Plugs.DeviceEndpointRedirect
  alias NervesHubWeb.Plugs.ImAlive

  plug(ImAlive)

  plug(Sentry.PlugContext)

  plug(DeviceEndpointRedirect)
end
