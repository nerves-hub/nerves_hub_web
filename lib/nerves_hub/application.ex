defmodule NervesHub.Application do
  use Application

  require Logger

  @env Mix.env()

  def start(_type, _args) do
    :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{config: %{}})

    vapor = NervesHub.Config.load!()

    case System.cmd("fwup", ["--version"]) do
      {_, 0} ->
        Logger.debug("fwup was found")

      _ ->
        raise "fwup could not be found in the $PATH. This is a requirement of NervesHubWeb and cannot start otherwise"
    end

    if @env != :test do
      :opentelemetry_cowboy.setup()
    end

    Application.put_env(:nerves_hub, :host, vapor.web_endpoint.url_host)
    Application.put_env(:nerves_hub, :port, vapor.web_endpoint.url_port)
    Application.put_env(:nerves_hub, :from_email, vapor.nerves_hub.from_email)
    Application.put_env(:nerves_hub, :app, vapor.nerves_hub.app)
    Application.put_env(:nerves_hub, :deploy_env, vapor.nerves_hub.deploy_env)

    Application.put_env(:sentry, :dsn, vapor.sentry.dsn_url)
    Application.put_env(:sentry, :environment_name, vapor.nerves_hub.deploy_env)
    Application.put_env(:sentry, :included_environments, vapor.sentry.included_environments)

    children =
      [
        {Cluster.Supervisor, [vapor.libcluster.topologies, [name: NervesHub.ClusterSupervisor]]},
        {Registry, keys: :unique, name: NervesHub.Devices},
        {Registry, keys: :unique, name: NervesHub.DeviceLinks},
        {Finch, name: Swoosh.Finch}
      ] ++
        metrics(@env, vapor) ++
        [
          {NervesHub.RateLimit, vapor.rate_limit},
          NervesHub.LoadBalancer,
          NervesHub.Supervisor,
          NervesHub.Tracker
        ] ++ endpoints(@env, vapor)

    opts = [strategy: :one_for_one, name: NervesHub.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    NervesHubWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp metrics(:test, _), do: []

  defp metrics(_env, vapor) do
    [{NervesHub.Metrics, vapor.statsd}]
  end

  defp endpoints(:test, _) do
    [
      NervesHub.Devices.Supervisor,
      NervesHubWeb.DeviceEndpoint,
      NervesHubWeb.Endpoint
    ]
  end

  defp endpoints(_, vapor) do
    socket_drano_config = vapor.socket_drano
    socket_strategy = {:percentage, socket_drano_config.percentage, socket_drano_config.time}

    case vapor.nerves_hub.app do
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
