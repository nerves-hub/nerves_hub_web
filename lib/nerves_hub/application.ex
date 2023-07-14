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

    if @env != :test do
      :opentelemetry_cowboy.setup()
      OpentelemetryPhoenix.setup(adapter: :cowboy2)
      OpentelemetryEcto.setup([:nerves_hub, :repo])
      OpentelemetryOban.setup()
    end

    children =
      [
        {Registry, keys: :unique, name: NervesHub.Devices},
        {Registry, keys: :unique, name: NervesHub.DeviceLinks}
      ] ++
        metrics(@env) ++
        [
          NervesHub.Supervisor,
          NervesHub.Tracker
        ] ++ endpoints(@env)

    opts = [strategy: :one_for_one, name: NervesHub.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    NervesHubWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp metrics(:test), do: []

  defp metrics(_env) do
    [NervesHub.Metrics]
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
