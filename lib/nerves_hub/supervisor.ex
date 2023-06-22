defmodule NervesHub.Supervisor do
  use Supervisor

  require Logger

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, :undefined)
  end

  def init(:undefined) do
    pubsub_config = Application.get_env(:nerves_hub, NervesHub.PubSub)

    children = [
      NervesHub.Repo,
      {Phoenix.PubSub, pubsub_config},
      {Task.Supervisor, name: NervesHub.TaskSupervisor},
      {Oban, configure_oban()}
    ]

    opts = [strategy: :one_for_one, name: NervesHub.Supervisor]
    Supervisor.init(children, opts)
  end

  defp configure_oban() do
    Application.get_env(:nerves_hub, Oban, [])
  end
end
