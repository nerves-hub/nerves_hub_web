defmodule NervesHub.ManagedDeployments.Monitor do
  @moduledoc """
  Deployment Monitor starts a deployment orchestrator per deployment

  Listens for new deployments and starts as necessary
  """

  use GenServer

  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeploymentDynamicSupervisor
  alias NervesHub.ManagedDeployments.Orchestrator
  alias Phoenix.PubSub
  alias Phoenix.Socket.Broadcast

  defmodule State do
    defstruct [:deployments]
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_) do
    _ = PubSub.subscribe(NervesHub.PubSub, "deployment_group:monitor")

    {:ok, %State{}, {:continue, :boot}}
  end

  def handle_continue(:boot, state) do
    deployments =
      Enum.into(ManagedDeployments.all(), %{}, fn deployment ->
        {:ok, orchestrator_pid} =
          DynamicSupervisor.start_child(
            ManagedDeploymentDynamicSupervisor,
            {ManagedDeployments.Orchestrator, deployment}
          )

        {deployment.id, %{orchestrator_pid: orchestrator_pid}}
      end)

    {:noreply, %{state | deployments: deployments}}
  end

  def handle_info(%Broadcast{event: "deployment_groups/new", payload: payload}, state) do
    {:ok, deployment} = ManagedDeployments.get(payload.deployment_id)

    {:ok, orchestrator_pid} =
      DynamicSupervisor.start_child(
        ManagedDeploymentDynamicSupervisor,
        {ManagedDeployments.Orchestrator, deployment}
      )

    deployments =
      Map.put(state.deployments, deployment.id, %{orchestrator_pid: orchestrator_pid})

    {:noreply, %{state | deployments: deployments}}
  end

  def handle_info(%Broadcast{event: "deployment_groups/delete", payload: payload}, state) do
    pid = GenServer.whereis(Orchestrator.name(payload.deployment_id))
    _ = DynamicSupervisor.terminate_child(ManagedDeploymentDynamicSupervisor, pid)
    deployments = Map.delete(state.deployments, payload.deployment_id)
    {:noreply, %{state | deployments: deployments}}
  end
end
