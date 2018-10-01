defmodule NervesHubCore.Application do
  use Application

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec

    pubsub_config = Application.get_env(:nerves_hub_core, NervesHubWeb.PubSub)
    firmware_gc_config = Application.get_env(:nerves_hub_core, NervesHubCore.Firmwares.GC, [])

    # Define workers and child supervisors to be supervised
    children = [
      # Start the Ecto repository
      supervisor(NervesHubCore.Repo, []),
      supervisor(Phoenix.PubSub.PG2, [pubsub_config[:name], pubsub_config]),
      {NervesHubCore.Firmwares.GC, firmware_gc_config},
      {Task.Supervisor, name: NervesHubCore.TaskSupervisor}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: NervesHubCore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
