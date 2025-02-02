defmodule NervesHub.Deployments.Distributed.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    children = [
      ProcessHub.child_spec(%ProcessHub{hub_id: :deployment_orchestrators}),
      NervesHub.Deployments.Distributed.Monitor
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
