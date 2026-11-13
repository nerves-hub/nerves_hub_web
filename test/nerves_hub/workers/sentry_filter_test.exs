defmodule NervesHub.Workers.SentryFilterTest do
  use ExUnit.Case, async: true

  alias NervesHub.Workers.DeliverWebhook
  alias NervesHub.Workers.FirmwareDeltaBuilder
  alias NervesHub.Workers.SentryFilter

  defp job(attempt, max_attempts), do: %Oban.Job{attempt: attempt, max_attempts: max_attempts}

  test "the delta builder is reported on its final attempt only" do
    refute SentryFilter.report_error?(FirmwareDeltaBuilder, job(1, 3))
    refute SentryFilter.report_error?(FirmwareDeltaBuilder, job(2, 3))
    assert SentryFilter.report_error?(FirmwareDeltaBuilder, job(3, 3))
  end

  test "other workers are reported on every attempt" do
    assert SentryFilter.report_error?(DeliverWebhook, job(1, 3))
  end

  test "a job whose worker Sentry could not resolve is reported" do
    assert SentryFilter.report_error?(nil, job(1, 3))
  end

  test "it is the callback Sentry's Oban integration uses" do
    oban = Application.fetch_env!(:sentry, :integrations)[:oban]

    assert oban[:should_report_error_callback] == (&SentryFilter.report_error?/2)
  end
end
