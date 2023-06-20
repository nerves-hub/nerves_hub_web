defmodule NervesHub.Application do
  use Application

  require Logger

  @env Mix.env()

  def start(_type, _args) do
    case System.cmd("fwup", ["--version"]) do
      {_, 0} ->
        Logger.debug("fwup was found")

      _ ->
        raise "fwup could not be found in the $PATH. This is a requirement of NervesHubWeb and cannot start otherwise"
    end

    children =
      [
        NervesHub.Metrics,
        NervesHub.Supervisor,
        {Registry, keys: :unique, name: NervesHub.Devices},
        NervesHub.Tracker
      ] ++ endpoints(@env)

    opts = [strategy: :one_for_one, name: NervesHub.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    NervesHubWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp endpoints(:test) do
    [
      NervesHub.Devices.Supervisor,
      NervesHubWeb.API.Endpoint,
      NervesHubWeb.DeviceEndpoint,
      NervesHubWeb.Endpoint
    ]
  end

  defp endpoints(_) do
    case Application.get_env(:nerves_hub, :app) do
      "all" ->
        [
          NervesHub.Deployments.Supervisor,
          NervesHub.Devices.Supervisor,
          NervesHubWeb.API.Endpoint,
          NervesHubWeb.DeviceEndpoint,
          NervesHubWeb.Endpoint
        ]

      "api" ->
        [NervesHubWeb.API.Endpoint]

      "device" ->
        [
          NervesHub.Deployments.Supervisor,
          NervesHub.Devices.Supervisor,
          NervesHubWeb.DeviceEndpoint
        ]

      "web" ->
        [NervesHubWeb.Endpoint]
    end
  end
end
