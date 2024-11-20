defmodule NervesHub.ManagedDeployments.Monitor do
  @moduledoc """
  Deployment Monitor starts a deployment orchestrator per deployment

  Listens for new deployment groups and starts as necessary
  """

  use GenServer

  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeploymentDynamicSupervisor
  alias NervesHub.ManagedDeployments.Orchestrator
  alias Phoenix.PubSub
  alias Phoenix.Socket.Broadcast

  defmodule State do
    defstruct [:deployment_groups]
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_) do
    _ = PubSub.subscribe(NervesHub.PubSub, "deployment_group:monitor")

    {:ok, %State{}, {:continue, :boot}}
  end

  def handle_continue(:boot, state) do
    deployment_groups =
      Enum.into(ManagedDeployments.all(), %{}, fn deployment_group ->
        {:ok, orchestrator_pid} =
          DynamicSupervisor.start_child(
            ManagedDeploymentDynamicSupervisor,
            {ManagedDeployments.Orchestrator, deployment_group}
          )

        {deployment_group.id, %{orchestrator_pid: orchestrator_pid}}
      end)

    {:noreply, %{state | deployment_groups: deployment_groups}}
  end

  def handle_info(%Broadcast{event: "deployments/new", payload: payload}, state) do
    {:ok, deployment_group} = ManagedDeployments.get(payload.deployment_id)

    {:ok, orchestrator_pid} =
      DynamicSupervisor.start_child(
        ManagedDeploymentDynamicSupervisor,
        {ManagedDeployments.Orchestrator, deployment_group}
      )

    deployment_groups =
      Map.put(state.deployment_groups, deployment_group.id, %{orchestrator_pid: orchestrator_pid})

    {:noreply, %{state | deployment_groups: deployment_groups}}
  end

  def handle_info(%Broadcast{event: "deployments/delete", payload: payload}, state) do
    pid = GenServer.whereis(Orchestrator.name(payload.deployment_id))
    _ = DynamicSupervisor.terminate_child(ManagedDeploymentDynamicSupervisor, pid)
    deployment_groups = Map.delete(state.deployment_groups, payload.deployment_id)
    {:noreply, %{state | deployment_groups: deployment_groups}}
  end
end
