defmodule NervesHub.Application do
  use Application

  require Logger

  def start(_type, _args) do
    case System.cmd("fwup", ["--version"]) do
      {_, 0} ->
        Logger.debug("fwup was found")

      _ ->
        raise "fwup could not be found in the $PATH. This is a requirement of NervesHubWeb and cannot start otherwise"
    end

    children = [
      NervesHub.Metrics,
      NervesHub.Supervisor
    ] ++ endpoints()

    opts = [strategy: :one_for_one, name: NervesHub.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    NervesHubWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp endpoints() do
    case Application.get_env(:nerves_hub, :app) do
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
