defmodule NervesHub.ManagedDeployments.Distributed.OrchestratorRegistration do
  @moduledoc """
  Registers deployment orchestrators with `ProcessHub`.

  Runs at startup, and then shuts down.
  """

  use GenServer

  require Logger

  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Distributed.Orchestrator

  def child_spec(_) do
    %{
      id: OrchestratorRegistration,
      start: {__MODULE__, :start_link, []},
      restart: :permanent
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
  def handle_info(:start_orchestrators, state) do
    start_orchestrators()

    Process.send_after(self(), :monitor_orchestrators, interval_with_jitter())

    {:noreply, state}
  end

  def handle_info(:monitor_orchestrators, state) do
    check_running_orchestrators()

    Process.send_after(self(), :monitor_orchestrators, interval_with_jitter())

    {:noreply, state}
  end

  def check_running_orchestrators() do
    process_count = ProcessHub.process_list(:deployment_orchestrators, :global) |> Enum.count()
    deployment_count = ManagedDeployments.should_run_orchestrator() |> Enum.count()

    if process_count != deployment_count do
      _ =
        Sentry.capture_message("Not enough Orchestrator processes are running",
          extra: %{process_count: process_count, deployment_count: deployment_count},
          result: :none
        )

      start_orchestrators()
    end

    :ok
  end

  @spec start_orchestrators() :: :ok
  def start_orchestrators() do
    ManagedDeployments.should_run_orchestrator()
    |> Enum.map(&Orchestrator.child_spec(&1))
    |> Enum.map(&await_start(&1))
    |> report_errors()
  end

  defp await_start(spec) do
    ProcessHub.start_child(:deployment_orchestrators, spec, async_wait: true)
    |> ProcessHub.await()
    |> case do
      {:error, {:already_started, _} = info} ->
        # :already_started is an ok (good) result
        {:ok, info}

      other ->
        other
    end
  end

  defp report_errors(results) do
    errors = Enum.filter(results, fn result -> elem(result, 0) == :error end)

    _ =
      if Enum.any?(errors) do
        Logger.error("Orchestrators failed to start : #{inspect(errors)}")

        Sentry.capture_message("Orchestrators failed to start",
          extra: %{results: errors},
          result: :none
        )
      end

    :ok
  end

  # random seconds between 13 and 17 minutes
  defp interval_with_jitter() do
    (13 * 60)..(17 * 60)
    |> Enum.random()
    |> :timer.seconds()
  end
end
