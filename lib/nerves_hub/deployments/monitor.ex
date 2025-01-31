defmodule NervesHub.Deployments.Monitor do
  @moduledoc """
  Deployment Monitor starts a deployment orchestrator per deployment

  Listens for new deployments and starts as necessary
  """

  use GenServer

  alias NervesHub.Deployments
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Deployments.Orchestrator

  def start_link(_) do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_) do
    {:ok, %{}, {:continue, :boot}}
  end

  def handle_continue(:boot, state) do
    Deployments.all_active()
    |> Enum.each(fn deployment ->
      start_orchestrator(deployment)
    end)

    {:noreply, state}
  end

  def start_orchestrator(%Deployment{is_active: true} = deployment) do
    Horde.DynamicSupervisor.start_child(
      NervesHub.DistributedSupervisor,
      Orchestrator.child_spec(deployment)
    )
  end

  def start_orchestrator(_) do
    :ok
  end

  def stop_orchestrator(deployment) do
    message = %Phoenix.Socket.Broadcast{
      topic: "deployment:#{deployment.id}",
      event: "deployment/deactivated"
    }

    Phoenix.PubSub.broadcast(NervesHub.PubSub, "deployment:#{deployment.id}", message)
  end
end
