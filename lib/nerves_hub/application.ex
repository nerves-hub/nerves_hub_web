defmodule NervesHub.Application do
  use Application

  require Logger

  @env Mix.env()

  def start(_type, _args) do
    :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{config: %{}})

    vapor_config = NervesHub.Config.load!()

    case System.cmd("fwup", ["--version"]) do
      {_, 0} ->
        Logger.debug("fwup was found")

      _ ->
        raise "fwup could not be found in the $PATH. This is a requirement of NervesHubWeb and cannot start otherwise"
    end

    if @env != :test do
      :opentelemetry_cowboy.setup()
    end

    Application.put_env(:nerves_hub, :host, vapor_config.web_endpoint.url_host)
    Application.put_env(:nerves_hub, :port, vapor_config.web_endpoint.url_port)
    Application.put_env(:nerves_hub, :from_email, vapor_config.nerves_hub.from_email)
    Application.put_env(:nerves_hub, :app, vapor_config.nerves_hub.app)
    Application.put_env(:nerves_hub, :deploy_env, vapor_config.nerves_hub.deploy_env)

    Application.put_env(:sentry, :dsn, vapor_config.sentry.dsn_url)
    Application.put_env(:sentry, :environment_name, vapor_config.nerves_hub.deploy_env)

    children =
      [
        {Registry, keys: :unique, name: NervesHub.Devices},
        {Registry, keys: :unique, name: NervesHub.DeviceLinks},
        {Finch, name: Swoosh.Finch}
      ] ++
        metrics(@env, vapor_config) ++
        [
          {NervesHub.RateLimit, vapor_config.rate_limit},
          NervesHub.LoadBalancer,
          NervesHub.Supervisor,
          NervesHub.Tracker
        ] ++ endpoints(@env, vapor_config)

    opts = [strategy: :one_for_one, name: NervesHub.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    NervesHubWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp metrics(:test, _), do: []

  defp metrics(_env, vapor_config) do
    [{NervesHub.Metrics, vapor_config.statsd}]
  end

  defp endpoints(:test, _) do
    [
      NervesHub.Devices.Supervisor,
      NervesHubWeb.DeviceEndpoint,
      NervesHubWeb.Endpoint
    ]
  end

  defp endpoints(_, vapor_config) do
    socket_drano_config = vapor_config.socket_drano
    socket_strategy = {:percentage, socket_drano_config.percentage, socket_drano_config.time}

    case vapor_config.nerves_hub.app do
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
