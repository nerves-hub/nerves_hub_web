defmodule NervesHub.Application do
  use Application

  alias NervesHub.Config

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
    end

    :fuse.install(:ecto, {{:standard, 20, 1000}, {:reset, 5000}})

    children =
      [
        {Registry, keys: :unique, name: NervesHub.Devices},
        {Registry, keys: :unique, name: NervesHub.DeviceLinks},
        {Finch, name: Swoosh.Finch}
      ] ++
        metrics(@env) ++
        [
          NervesHub.RateLimit,
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
      NervesHubWeb.DeviceEndpoint,
      NervesHubWeb.Endpoint
    ]
  end

  defp endpoints(_) do
    vapor_config = Vapor.load!(Config)
    socket_drano_config = vapor_config.socket_drano
    socket_strategy = {:percentage, socket_drano_config.percentage, socket_drano_config.time}

    case Application.get_env(:nerves_hub, :app) do
      "all" ->
        [
          NervesHub.Deployments.Supervisor,
          NervesHub.Devices.Supervisor,
          NervesHubWeb.DeviceEndpoint,
          NervesHubWeb.Endpoint,
          {SocketDrano, refs: [NervesHubWeb.DeviceEndpoint.HTTPS], strategy: socket_strategy}
        ]

      "device" ->
        [
          NervesHub.Deployments.Supervisor,
          NervesHub.Devices.Supervisor,
          NervesHubWeb.DeviceEndpoint,
          {SocketDrano, refs: [NervesHubWeb.DeviceEndpoint.HTTPS, strategy: socket_strategy]}
        ]

      "web" ->
        [NervesHubWeb.Endpoint]
    end
  end
end
