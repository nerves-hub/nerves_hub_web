defmodule NervesHub.Application do
  use Application

  require Logger

  def start(_type, _args) do
    case System.cmd("fwup", ["--version"], env: []) do
      {_, 0} ->
        Logger.debug("fwup was found")

      _ ->
        raise "fwup could not be found in the $PATH. This is a requirement of NervesHubWeb and cannot start otherwise"
    end

    setup_open_telemetry()

    _ =
      :logger.add_handler(:my_sentry_handler, Sentry.LoggerHandler, %{
        config: %{metadata: [:file, :line]}
      })

    NervesHub.Logger.attach()

    topologies = Application.get_env(:libcluster, :topologies, [])

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
          {Cluster.Supervisor, [topologies]},
          {Task.Supervisor, name: NervesHub.TaskSupervisor},
          {Oban, Application.fetch_env!(:nerves_hub, Oban)},
          NervesHubWeb.Presence,
          {NervesHub.RateLimit.LogLines,
           [clean_period: :timer.minutes(5), key_older_than: :timer.hours(1)]}
        ] ++
        deployments_orchestrator(deploy_env()) ++
        endpoints(deploy_env())

    opts = [strategy: :one_for_one, name: NervesHub.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp setup_open_telemetry() do
    if System.get_env("ECTO_IPV6") do
      :ok = :httpc.set_option(:ipfamily, :inet6fb4)
    end

    :ok = NervesHub.Telemetry.Customizations.setup()

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

  defp ecto_migrations() do
    [
      Supervisor.child_spec(
        {Ecto.Migrator,
         repos: [NervesHub.Repo],
         skip: Application.get_env(:nerves_hub, :database_auto_migrator) != true,
         id: NervesHub.RepoMigrator},
        id: :repo_migrator
      ),
      Supervisor.child_spec(
        {Ecto.Migrator,
         repos: [NervesHub.AnalyticsRepo],
         skip: Application.get_env(:nerves_hub, :analytics_enabled) != true},
        id: :analytics_repo_migrator
      )
    ]
  end

  defp ecto_repos() do
    [NervesHub.Repo, NervesHub.ObanRepo] ++
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
      ["device"] ->
        []

      _ ->
        [
          ProcessHub.child_spec(%ProcessHub{hub_id: :deployment_orchestrators}),
          NervesHub.ManagedDeployments.Distributed.OrchestratorRegistration
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
        [NervesHubWeb.DeviceEndpoint]

      "web" ->
        [NervesHubWeb.Endpoint]
    end
  end

  defp deploy_env(), do: Application.get_env(:nerves_hub, :deploy_env)
end
