defmodule NervesHub.Deployments.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    children = [
      {Registry, keys: :unique, name: NervesHub.Deployments},
      NervesHub.Deployments.Monitor,
      {DynamicSupervisor, strategy: :one_for_one, name: NervesHub.DeploymentDynamicSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
