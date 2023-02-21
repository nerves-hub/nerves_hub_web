defmodule NervesHubDevice.Application do
  use Application

  def start(_type, _args) do
    children = [
      #      NervesHubDeviceWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: NervesHubDevice.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    NervesHubDeviceWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
