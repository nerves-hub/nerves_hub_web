defmodule NervesHubAPI.Application do
  use Application

  def start(_type, _args) do
    children = [
      #      NervesHubAPIWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: NervesHubAPI.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    NervesHubAPIWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
