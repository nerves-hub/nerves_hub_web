defmodule NervesHubWWW.Application do
  use Application

  def start(_type, _args) do
    NervesHubWebCore.CertificateAuthority.start_pool()

    children = endpoints()

    opts = [strategy: :one_for_one, name: NervesHubWWW.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    NervesHubWWWWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp endpoints() do
    case Application.get_env(:nerves_hub_web_core, :app) do
      "all" ->
        [
          NervesHubAPIWeb.Endpoint,
          NervesHubDeviceWeb.Endpoint,
          NervesHubWWWWeb.Endpoint
        ]

      "api" ->
        [NervesHubAPIWeb.Endpoint]

      "device" ->
        [NervesHubDeviceWeb.Endpoint]

      "web" ->
        [NervesHubWWWWeb.Endpoint]
    end
  end
end
