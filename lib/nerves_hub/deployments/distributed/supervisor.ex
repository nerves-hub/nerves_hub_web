defmodule NervesHub.Deployments.Distributed.Supervisor do
  @moduledoc false

  use Supervisor

  alias NervesHub.Deployments.Distributed.OrchestratorRegistration

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    children = [
      ProcessHub.child_spec(%ProcessHub{hub_id: :deployment_orchestrators}),
      OrchestratorRegistration
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
