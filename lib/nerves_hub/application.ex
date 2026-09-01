defmodule NervesHub.Application do
  use Application

  alias NervesHub.Analytics.Buffer
  alias NervesHub.DeviceLink.Handlers
  alias NervesHub.Devices.DeviceConnectionHistory
  alias NervesHub.Devices.DeviceMessage
  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.Devices.LogLine
  alias NervesHub.ErrorReports.ErrorReport
  alias NervesHub.ErrorReports.GroupBuffer
  alias NervesHub.ManagedDeployments.Distributed.OrchestratorRegistration
  alias NervesHub.PlugAttack.Storage, as: PlugAttackStorage
  alias NervesHub.RateLimit.ErrorReports, as: ErrorReportLimit
  alias NervesHub.RateLimit.LogLines
  alias NervesHub.RateLimit.Metrics, as: MetricsLimit
  alias NervesHub.Telemetry.Customizations
  alias PlugAttack.Storage.Ets, as: PlugAttackEts

  require Logger

  def start(_type, _args) do
    case System.cmd("fwup", ["--version"], env: []) do
      {_, 0} ->
        Logger.debug("fwup was found")

      _ ->
        raise "fwup could not be found in the $PATH. This is a requirement of NervesHubWeb and cannot start otherwise"
    end

    setup_open_telemetry()
    _ = setup_logging()

    children =
      [{Finch, name: Swoosh.Finch}] ++
        ecto_migrations() ++
        NervesHub.StatsdMetricsReporter.config() ++
        [
          NervesHub.MetricsPoller.child_spec(),
          NervesHub.RateLimit
        ] ++
        ecto_repos() ++
        [
          {Phoenix.PubSub, name: NervesHub.PubSub},
          # Ahead of the group tree: `RateLimitPubSub` applies peer throttle
          # increments into this storage the moment it joins its group.
          {PlugAttackEts, name: PlugAttackStorage, clean_period: 60_000},
          NervesHub.GroupSupervisor,
          {Cluster.Supervisor, [libcluster_topology()]},
          {Task.Supervisor, name: NervesHub.TaskSupervisor},
          {Oban, oban_opts()},
          NervesHubWeb.Presence,
          # Per-product health evaluators, started on demand where device
          # connections land; see NervesHub.Devices.HealthEvaluator.
          {Registry, keys: :unique, name: NervesHub.Devices.HealthEvaluator.Registry},
          {DynamicSupervisor, name: NervesHub.Devices.HealthEvaluator.Supervisor, strategy: :one_for_one},
          {LogLines, [clean_period: to_timeout(minute: 5), key_older_than: to_timeout(hour: 1)]},
          {ErrorReportLimit, [clean_period: to_timeout(minute: 5), key_older_than: to_timeout(hour: 1)]},
          {MetricsLimit, [clean_period: to_timeout(minute: 5), key_older_than: to_timeout(hour: 1)]}
        ] ++
        analytics_buffers() ++
        device_link_handlers() ++
        deployments_orchestrator(deploy_env()) ++
        endpoints(deploy_env())

    opts = [strategy: :one_for_one, name: NervesHub.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp setup_logging() do
    # Sentrys duplicate log handler checking (in their lib) runs before our application
    # has started, so instead, lets just remove the handler if it exists
    _ =
      if Application.get_env(:sentry, :enable_logs, false) do
        :logger.remove_handler(:sentry_log_handler)
      end

    :ok =
      :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{
        config: %{metadata: [:file, :line]}
      })

    :ok =
      :logger.add_primary_filter(:filter_ssl_handshake, {&NervesHub.Logger.ssl_log_filter/2, []})

    NervesHub.Logger.attach()
  end

  # Every node needs the scope so it can read who the handlers are; only nodes
  # carrying the platform stack join as one. Device nodes hold connections and
  # dispatch locally today, so joining would be harmless — but saying so here
  # keeps the handler pool an explicit decision rather than an accident.
  defp device_link_handlers() do
    scope = [Handlers.scope_spec()]

    case Application.get_env(:nerves_hub, :app) do
      "device" -> scope
      _ -> scope ++ [Handlers]
    end
  end

  defp setup_open_telemetry() do
    if System.get_env("ECTO_IPV6") do
      :ok = :httpc.set_option(:ipfamily, :inet6fb4)
    end

    :ok = Customizations.setup()

    :ok = OpentelemetryBandit.setup()
    :ok = OpentelemetryPhoenix.setup(adapter: :bandit)
    :ok = OpentelemetryOban.setup(trace: [:jobs])

    :ok =
      NervesHub.Repo.config()
      |> Keyword.fetch!(:telemetry_prefix)
      |> OpentelemetryEcto.setup(db_statement: :enabled)

    :ok
  end

  def config_change(changed, _new, removed) do
    NervesHubWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp libcluster_topology() do
    repo_config =
      NervesHub.Repo.config()
      |> Keyword.take([:hostname, :username, :password, :database, :port, :ssl])
      |> Keyword.put(:parameters, [])
      |> Keyword.put(:channel_name, "nerves_hub_clustering")

    [
      app: [
        strategy: LibclusterPostgres.Strategy,
        config: repo_config
      ]
    ]
  end

  defp oban_opts() do
    config = Application.fetch_env!(:nerves_hub, Oban)

    case Application.get_env(:nerves_hub, :app) do
      "device" ->
        config
        |> Keyword.put(:queues, [])
        |> Keyword.put(:peer, false)

      _ ->
        config
    end
  end

  defp ecto_migrations() do
    [
      Supervisor.child_spec(
        {Ecto.Migrator,
         repos: [NervesHub.Repo], skip: Application.get_env(:nerves_hub, :database_auto_migrator) != true},
        id: :repo_migrator
      ),
      Supervisor.child_spec(
        {Ecto.Migrator,
         repos: [NervesHub.AnalyticsRepo], skip: Application.get_env(:nerves_hub, :analytics_auto_migrator) != true},
        id: :analytics_repo_migrator
      )
    ]
  end

  # Batches the fleet-scale analytics write paths. Only started where there
  # is a ClickHouse to write to - callers no-op on the same `:analytics_enabled`
  # flag.
  defp analytics_buffers() do
    if Application.get_env(:nerves_hub, :analytics_enabled) do
      opts = Application.get_env(:nerves_hub, :analytics_buffer, [])

      [
        Buffer.child_spec([schema: DeviceConnectionHistory] ++ opts),
        Buffer.child_spec([schema: DeviceMessage] ++ opts),
        Buffer.child_spec([schema: LogLine] ++ opts),
        Buffer.child_spec([schema: ErrorReport] ++ opts),
        Buffer.child_spec([schema: DeviceMetric] ++ opts),
        # Writes PostgreSQL, not ClickHouse, and is here anyway: it is the other
        # half of the same write path, and the extension that feeds it is gated
        # on the same flag. Started without a ClickHouse to pair with, it would
        # only ever count occurrences nothing recorded.
        GroupBuffer.child_spec([])
      ]
    else
      []
    end
  end

  defp ecto_repos() do
    [NervesHub.Repo] ++
      if Application.get_env(:nerves_hub, :analytics_enabled) do
        [NervesHub.AnalyticsRepo]
      else
        []
      end
  end

  defp deployments_orchestrator("test"), do: []

  # Only run the `ProcessHub` supervisor on the `web` or `all` nodes only.
  defp deployments_orchestrator(_) do
    case Application.get_env(:nerves_hub, :app) do
      "device" ->
        []

      _ ->
        [
          ProcessHub.child_spec(%ProcessHub{hub_id: :deployment_orchestrators}),
          OrchestratorRegistration
        ]
    end
  end

  defp endpoints("test") do
    [
      NervesHubWeb.DeviceEndpoint,
      NervesHubWeb.Endpoint
    ]
  end

  defp endpoints(_) do
    case Application.get_env(:nerves_hub, :app) do
      "all" ->
        [
          NervesHubWeb.DeviceEndpoint,
          NervesHubWeb.Endpoint
        ]

      "device" ->
        [
          NervesHubWeb.DeviceEndpoint,
          NervesHubWeb.HealthCheckEndpoint
        ]

      "web" ->
        [NervesHubWeb.Endpoint]
    end
  end

  defp deploy_env(), do: Application.get_env(:nerves_hub, :deploy_env)
end
