defmodule NervesHub.Application do
  use Application

  def start(_type, _args) do
    NervesHub.CertificateAuthority.start_pool()

    children = [NervesHub.Supervisor] ++ endpoints()

    opts = [strategy: :one_for_one, name: NervesHub.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    NervesHubWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp endpoints() do
    case Application.get_env(:nerves_hub_www, :app) do
      "all" ->
        [
          NervesHubWeb.API.Endpoint,
          NervesHubWeb.DeviceEndpoint,
          NervesHubWeb.Endpoint
        ]

      "api" ->
        [NervesHubWeb.API.Endpoint]

      "device" ->
        [NervesHubWeb.DeviceEndpoint]

      "web" ->
        [NervesHubWeb.Endpoint]
    end
  end
end
