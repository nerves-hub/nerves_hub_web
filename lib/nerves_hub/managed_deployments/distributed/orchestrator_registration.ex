defmodule NervesHub.ManagedDeployments.Distributed.OrchestratorRegistration do
  @moduledoc """
  Registers deployment orchestrators with `ProcessHub`.

  Runs at startup, and then shuts down.
  """

  use GenServer

  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Distributed.Orchestrator

  require Logger

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
          extra: %{process_count: process_count, deployment_count: deployment_count},
          result: :none
        )

      start_orchestrators()
    end

    :ok
  end

  # We need to filter out already running orchestrators, otherwise ProcessHub will fail
  # with a list of `:already_started` orchestrator ids.
  #
  # I've also added `check_existing: false` to avoid starting already running orchestrators, as
  # noted in the ProcessHub documentation.
  @spec start_orchestrators() :: :ok
  def start_orchestrators() do
    should_run =
      ManagedDeployments.should_run_orchestrator()
      |> Enum.map(&Orchestrator.child_spec/1)

    currently_running =
      ProcessHub.process_list(:deployment_orchestrators, :global)
      |> Enum.map(fn {key, _info} -> key end)

    requires_starting =
      Enum.reject(should_run, fn spec -> spec.id in currently_running end)

    ProcessHub.start_children(:deployment_orchestrators, requires_starting, awaitable: true, check_existing: false)
    |> ProcessHub.Future.await()
    |> ProcessHub.StartResult.format()
    |> report_errors()
  end

  defp report_errors({:ok, _started_list}) do
    :ok
  end

  defp report_errors({:error, errors, :rollback}) do
    report_errors({:error, errors})
  end

  defp report_errors({:error, errors}) do
    Logger.error("Orchestrators failed to start : #{inspect(errors)}")

    _ =
      Sentry.capture_message("Orchestrators failed to start",
        extra: %{results: errors},
        result: :none
      )

    :ok
  end

  # random seconds between 13 and 17 minutes
  defp interval_with_jitter() do
    (13 * 60)..(17 * 60)
    |> Enum.random()
    |> :timer.seconds()
  end
end
