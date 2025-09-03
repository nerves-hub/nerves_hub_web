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
      restart: :permanent,
      start: {__MODULE__, :start_link, []}
    }
  end

  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  @impl GenServer
  def init(_) do
    Process.send_after(self(), :start_orchestrators, to_timeout(second: 3))
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
          extra: %{deployment_count: deployment_count, process_count: process_count},
          result: :none
        )

      start_orchestrators()
    end

    :ok
  end

  @spec start_orchestrators() :: :ok
  def start_orchestrators() do
    ManagedDeployments.should_run_orchestrator()
    |> Enum.map(&Orchestrator.child_spec/1)
    |> Enum.map(&await_start/1)
    |> report_errors()
  end

  # :already_started is an ok (good) result
  # it's unclear which is the correct pattern matching to use
  defp await_start(spec) do
    ProcessHub.start_child(:deployment_orchestrators, spec, async_wait: true)
    |> ProcessHub.await()
    |> case do
      {:error, {:already_started, _} = info} ->
        {:ok, info}

      {:error, {{_id, _node, {:already_started, _pid}} = info, []}} ->
        {:ok, info}

      other ->
        other
    end
  end

  defp report_errors(results) do
    errors = Enum.filter(results, fn {status, _} -> status == :error end)

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
