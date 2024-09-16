defmodule NervesHubWeb.MetricsEndpoint do
  use Phoenix.Endpoint, otp_app: :nerves_hub

  plug(PromEx.Plug, prom_ex_module: NervesHub.PromEx)

  plug(NervesHubWeb.Plugs.DeviceEndpointRedirect)
end
