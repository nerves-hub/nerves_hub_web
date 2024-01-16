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

    topologies = Application.get_env(:libcluster, :topologies, [])

    children =
      [
        {Ecto.Migrator,
         repos: Application.fetch_env!(:nerves_hub, :ecto_repos),
         skip: Application.get_env(:nerves_hub, :database_auto_migrator) != true},
        {Registry, keys: :unique, name: NervesHub.Devices},
        {Registry, keys: :unique, name: NervesHub.DeviceLinks},
        {Finch, name: Swoosh.Finch}
      ] ++
        metrics(deploy_env()) ++
        [
          NervesHub.RateLimit,
          NervesHub.LoadBalancer,
          NervesHub.Repo,
          NervesHub.ObanRepo,
          {Phoenix.PubSub, name: NervesHub.PubSub},
          {Cluster.Supervisor, [topologies]},
          {Task.Supervisor, name: NervesHub.TaskSupervisor},
          {Oban, Application.fetch_env!(:nerves_hub, Oban)},
          NervesHub.Tracker,
          NervesHub.Devices.Supervisor
        ] ++
        deployments_supervisor(deploy_env()) ++
        endpoints(deploy_env())

    opts = [strategy: :one_for_one, name: NervesHub.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    NervesHubWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp metrics("test"), do: []

  defp metrics(_env) do
    [NervesHub.Metrics]
  end

  defp deployments_supervisor("test"), do: []

  defp deployments_supervisor(_) do
    [NervesHub.Deployments.Supervisor]
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
