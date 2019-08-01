defmodule NervesHubWebCore.Application do
  use Application

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    pubsub_config = Application.get_env(:nerves_hub_web_core, NervesHubWeb.PubSub)

    # Define workers and child supervisors to be supervised
    children = [
      # Start the Ecto repository
      NervesHubWebCore.Repo,
      {Phoenix.PubSub.PG2, pubsub_config},
      {Task.Supervisor, name: NervesHubWebCore.TaskSupervisor}
      # NervesHubWebCore.Scheduler
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: NervesHubWebCore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
