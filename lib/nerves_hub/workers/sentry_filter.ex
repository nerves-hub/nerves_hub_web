defmodule NervesHub.Workers.SentryFilter do
  @moduledoc """
  Decides which failed Oban jobs are reported to Sentry, as the Oban
  integration's `should_report_error_callback` (see `config/runtime.exs`).

  Sentry hears about every attempt that raises or returns `{:error, _}`. That
  is right for most workers, where a failure is a bug whether or not a retry
  gets past it. The workers listed here are reported on their final attempt
  only, because an earlier failure is routinely something a retry fixes.

  `NervesHub.Workers.FirmwareDeltaBuilder` downloads two firmware archives and
  unpacks them, so an attempt can fail on a DNS lookup or a node short of disk,
  and the next attempt, often on another node, succeeds. The worker marks the
  delta failed on its last attempt, and that is the failure worth hearing about.
  """

  alias NervesHub.Workers.FirmwareDeltaBuilder

  @final_attempt_only [FirmwareDeltaBuilder]

  @spec report_error?(module() | nil, Oban.Job.t()) :: boolean()
  def report_error?(worker, job) when worker in @final_attempt_only, do: job.attempt >= job.max_attempts
  def report_error?(_worker, _job), do: true
end
