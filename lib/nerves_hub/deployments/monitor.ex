defmodule NervesHub.Deployments.Monitor do
  @moduledoc """
  Deployment Monitor starts a deployment orchestrator per deployment

  Listens for new deployments and starts as necessary
  """

  use GenServer

  alias NervesHub.DeploymentDynamicSupervisor
  alias NervesHub.Deployments
  alias NervesHub.Deployments.Orchestrator
  alias NervesHub.InflightDeploymentCheckDynamicSupervisor
  alias Phoenix.PubSub
  alias Phoenix.Socket.Broadcast

  defmodule State do
    defstruct [:deployments]
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_) do
    _ = PubSub.subscribe(NervesHub.PubSub, "deployment:monitor")

    {:ok, %State{}, {:continue, :boot}}
  end

  def handle_continue(:boot, state) do
    deployments =
      Enum.into(Deployments.all(), %{}, fn deployment ->
        {:ok, orchestrator_pid} =
          DynamicSupervisor.start_child(
            DeploymentDynamicSupervisor,
            {Deployments.Orchestrator, deployment}
          )

        {:ok, calculator_pid} =
          DynamicSupervisor.start_child(
            InflightDeploymentCheckDynamicSupervisor,
            {Deployments.Calculator, deployment}
          )

        {deployment.id, %{orchestrator_pid: orchestrator_pid, calculator_pid: calculator_pid}}
      end)

    {:noreply, %{state | deployments: deployments}}
  end

  def handle_info(%Broadcast{event: "deployments/new", payload: payload}, state) do
    {:ok, deployment} = Deployments.get(payload.deployment_id)

    {:ok, orchestrator_pid} =
      DynamicSupervisor.start_child(
        DeploymentDynamicSupervisor,
        {Deployments.Orchestrator, deployment}
      )

    {:ok, calculator_pid} =
      DynamicSupervisor.start_child(
        InflightDeploymentCheckDynamicSupervisor,
        {Deployments.Calculator, deployment}
      )

    deployments =
      Map.put(state.deployments, deployment.id, %{
        orchestrator_pid: orchestrator_pid,
        calculator_pid: calculator_pid
      })

    {:noreply, %{state | deployments: deployments}}
  end

  def handle_info(%Broadcast{event: "deployments/delete", payload: payload}, state) do
    pid = GenServer.whereis(Orchestrator.name(payload.deployment_id))
    _ = DynamicSupervisor.terminate_child(DeploymentDynamicSupervisor, pid)
    deployments = Map.delete(state.deployments, payload.deployment_id)
    {:noreply, %{state | deployments: deployments}}
  end
end
