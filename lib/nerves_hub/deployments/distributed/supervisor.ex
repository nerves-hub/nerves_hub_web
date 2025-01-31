defmodule NervesHub.Deployments.Distributed.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    children = [
      NervesHub.Deployments.Distributed.Monitor,
      {Horde.Registry, [name: NervesHub.DeploymentsRegistry, keys: :unique]},
      {Horde.DynamicSupervisor,
       [
         name: NervesHub.DistributedSupervisor,
         strategy: :one_for_one,
         members: :auto,
         process_redistribution: :active,
         distribution_strategy: Horde.UniformQuorumDistribution
       ]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
