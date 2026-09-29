defmodule NervesHub.Workers.RequeueStrandedScriptRunners do
  @moduledoc """
  Gives a new pacer to any script run that has lost its own.

  A run's `NervesHub.Workers.ScriptRunnerDispatch` job is inserted once, in the
  transaction that creates the run, and keeps itself alive by snoozing. If it is
  discarded — attempts exhausted, or rescued by `Oban.Lifeline` after a node died
  holding it — nothing else would ever insert another, and the run would sit
  unfinished with no devices being dispatched.

  That also costs every other run: an unfinished run still counts towards the
  divisor each run's share of the concurrency ceiling is worked out from, so a
  stranded run throttles the runs that come after it. See
  `NervesHub.ScriptRunners.requeue_stranded_runs/0`.
  """

  use Oban.Worker,
    queue: :cleanup,
    max_attempts: 5,
    unique: [states: [:available, :scheduled, :executing, :suspended, :retryable]]

  alias NervesHub.ScriptRunners

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    case ScriptRunners.requeue_stranded_runs() do
      0 ->
        :ok

      count ->
        # Worth a line: reaching here means a pacer was lost, which is not
        # expected in the ordinary course of a run.
        Logger.info("Requeued #{count} stranded script #{runs(count)}")

        :ok
    end
  end

  defp runs(1), do: "run"
  defp runs(_many), do: "runs"
end
