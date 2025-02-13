defmodule NervesHub.Deployments.Distributed.OrchestratorRegistration do
  @moduledoc """
  Registers deployment orchestrators with `ProcessHub`.

  Runs at startup, and then shuts down.
  """

  use GenServer

  alias NervesHub.Deployments
  alias NervesHub.Deployments.Distributed.Orchestrator

  def child_spec(_) do
    %{
      id: OrchestratorRegistration,
      start: {__MODULE__, :start_link, []},
      restart: :transient
    }
  end

  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  @impl GenServer
  def init(_) do
    Process.send_after(self(), :start_orchestrators, :timer.seconds(3))
    {:ok, nil}
  end

  @impl GenServer
  def handle_info(:start_orchestrators, _) do
    _ =
      Deployments.should_run_in_distributed_orchestrator()
      |> Enum.map(fn deployment ->
        Orchestrator.child_spec(deployment)
      end)
      |> then(fn specs ->
        ProcessHub.start_children(:deployment_orchestrators, specs)
      end)

    {:stop, :shutdown, nil}
  end
end
