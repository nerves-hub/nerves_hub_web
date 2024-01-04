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
          {DNSCluster, query: Application.get_env(:nerves_hub, :dns_cluster_query) || :ignore},
          {Task.Supervisor, name: NervesHub.TaskSupervisor},
          {Oban, Application.fetch_env!(:nerves_hub, Oban)},
          NervesHub.Tracker
        ] ++
        endpoints(Application.get_env(:nerves_hub, :deploy_env))

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

  defp endpoints("test") do
    [
      NervesHub.Devices.Supervisor,
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
          NervesHubWeb.DeviceEndpoint,
          NervesHubWeb.Endpoint
        ] ++ device_socket_drainer()

      "device" ->
        [
          NervesHub.Deployments.Supervisor,
          NervesHub.Devices.Supervisor,
          NervesHubWeb.DeviceEndpoint
        ] ++ device_socket_drainer()

      "web" ->
        [NervesHubWeb.Endpoint]
    end
  end

  defp device_socket_drainer() do
    socket_drano_config = Application.get_env(:nerves_hub, :socket_drano)

    if socket_drano_config[:enabled] do
      socket_strategy =
        {:percentage, socket_drano_config[:percentage], socket_drano_config[:time]}

      [{SocketDrano, refs: [NervesHubWeb.DeviceEndpoint.HTTPS], strategy: socket_strategy}]
    else
      []
    end
  end

  defp deploy_env(), do: Application.get_env(:nerves_hub, :deploy_env)
end
