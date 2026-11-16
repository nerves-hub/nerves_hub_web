defmodule NervesHub.Workers.ExpireScriptRunnerOutput do
  @moduledoc """
  Clears script run output that has outlived its retention period.

  Output is whatever a script printed on a device, which can include
  credentials, so it is kept for a few days rather than for as long as the run
  is. The period is `SCRIPT_RUNNER_OUTPUT_DAYS_TO_RETAIN`; see
  `NervesHub.ScriptRunners.expire_output/2` for what is cleared and what stays.

  Each pass clears at most `SCRIPT_RUNNER_OUTPUT_EXPIRE_ROW_LIMIT` rows, so one pass
  after a large run is a bounded statement. A backlog is worked down over the
  passes that follow.
  """

  use Oban.Worker,
    queue: :cleanup,
    max_attempts: 5,
    unique: [states: [:available, :scheduled, :executing, :retryable]]

  alias NervesHub.ScriptRunners

  @default_days_to_retain 3
  @default_limit 100_000

  @impl Oban.Worker
  def perform(_job) do
    days = Application.get_env(:nerves_hub, :script_runner_output_days_to_retain, @default_days_to_retain)
    limit = Application.get_env(:nerves_hub, :script_runner_output_expire_row_limit, @default_limit)

    _ = ScriptRunners.expire_output(to_timeout(day: days), limit)

    :ok
  end
end
