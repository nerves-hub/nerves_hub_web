defmodule NervesHub.Deployments.Distributed.OrchestratorRegistration do
  @moduledoc """
  Registers deployment orchestrators with `ProcessHub`.

  Runs at startup, and then shuts down.
  """

  use GenServer

  alias NervesHub.Deployments
  alias NervesHub.Deployments.Distributed.Orchestrator

  def start_link(_) do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_) do
    Process.send_after(self(), :start_orchestrators, :timer.seconds(3))
    {:ok, nil}
  end

  def handle_info(:start_orchestrators, _) do
    Deployments.all_active()
    |> Enum.map(fn deployment ->
      Orchestrator.child_spec(deployment)
    end)
    |> then(fn specs ->
      ProcessHub.start_children(:deployment_orchestrators, specs)
    end)

    {:stop, :shutdown, nil}
  end
end
