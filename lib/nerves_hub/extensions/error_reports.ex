defmodule NervesHub.Extensions.ErrorReports do
  @moduledoc """
  Exceptions and explicit error reports from a device, grouped into issues.

  Version 0.1.0, and batched from the start:

      error_reports:report  %{"reports" => [%{"kind" => .., "reason" => ..}, ..]}

  Nothing goes the other way. The platform never asks for an error and never
  acknowledges one — a device with nothing to report sends nothing at all, which
  is what makes this cost an idle fleet nothing.

  ## Why there is no 0.0.1

  A supervisor restart storm produces a burst of crashes in one second, and
  those bursts are the interesting ones. The rate limit is on how *often* a
  device may send rather than how much it may say, so a message carrying
  twenty-five reports costs exactly what a message carrying one costs. A
  single-report version would throw most of a crash loop away and keep an
  arbitrary sample of it — the failure `NervesHub.Extensions.Logging.Batched`
  exists to correct, and not one worth repeating.

  See `docs/error_reports.md` for the contract clients are written against.
  """

  @behaviour NervesHub.Extensions

  alias NervesHub.DeviceLink.DeviceInfo
  # Aliased rather than used bare: this module is `Extensions.ErrorReports`,
  # and an unqualified `ErrorReports` next to it reads as a self-reference.
  alias NervesHub.ErrorReports, as: Reports
  alias NervesHub.RateLimit.ErrorReports, as: RateLimit

  require Logger

  @max_reports_per_message 25

  @rate_limit_tokens_per_sec 1
  @rate_limit_max_capacity 5
  @rate_limit_token_cost 1

  @doc "How many reports one message may carry."
  def max_reports_per_message(), do: @max_reports_per_message

  @impl NervesHub.Extensions
  def description() do
    """
    Report exceptions and errors to NervesHub, grouped into issues you can resolve.
    """
  end

  @impl NervesHub.Extensions
  def enabled?() do
    Application.get_env(:nerves_hub, :analytics_enabled)
  end

  @impl NervesHub.Extensions
  def attach(state) do
    {state, []}
  end

  @impl NervesHub.Extensions
  def detach(state) do
    {state, []}
  end

  # Nothing to store, and nothing charged for it. The budget is for the second a
  # device does have something to say, and spending it on an empty message would
  # take rate limiting further than it is meant to go.
  @impl NervesHub.Extensions
  def handle_in("report", %{"reports" => []}, state) do
    {state, []}
  end

  def handle_in("report", %{"reports" => reports}, state) when is_list(reports) do
    if allow?(state.device_info) do
      {kept, dropped} = Enum.split(reports, @max_reports_per_message)

      _ = Reports.record_batch(state.device_info, kept)
      _ = record_overflow(state.device_info, length(dropped))

      # Both branches end on an atom so nothing complex is discarded here.
      # Without it dialyzer reports the tuple this would otherwise return as an
      # unmatched return -- the same reason `Logging.Batched` does it.
      :noop
    end

    {state, []}
  end

  # A device on 0.1.0 sends batches. Anything else is a client that declared a
  # version it does not speak, which is worth a log line and not worth a crash:
  # `safe_dispatch/5` would rescue it into Sentry, and one device's confusion is
  # not a platform error.
  def handle_in("report", payload, state) do
    Logger.warning(
      "device #{state.device_info.device_id} declared error_reports 0.1.0 and sent #{inspect(payload, limit: 5)}"
    )

    {state, []}
  end

  @impl NervesHub.Extensions
  def handle_info(_msg, state) do
    {state, []}
  end

  @doc """
  Whether this device may send now.

  One token per message, whatever the message carries, and its own bucket rather
  than a share of the logging extension's. A device in a crash loop is producing
  both at once, and the two features starving each other at exactly the moment
  both matter would be the wrong way to spend one budget.
  """
  @spec allow?(DeviceInfo.t()) :: boolean()
  def allow?(%DeviceInfo{} = device_info) do
    case RateLimit.hit(
           "device_#{device_info.device_id}",
           @rate_limit_tokens_per_sec,
           @rate_limit_max_capacity,
           @rate_limit_token_cost
         ) do
      {:allow, _count} -> true
      {:deny, _ms} -> false
    end
  end

  defp record_overflow(_device_info, 0), do: :ok

  # Stored as a report of its own, so the gap is visible rather than silent.
  # Server-timestamped, unlike every other report here, because this one is an
  # observation the platform made and not something the device saw.
  defp record_overflow(device_info, dropped) do
    Reports.record(device_info, %{
      "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
      "kind" => "nerves_hub",
      "source" => "manual",
      "fingerprint" => "nerves_hub:dropped_error_reports",
      "reason" => "NervesHub dropped #{dropped} error reports: a message may carry at most #{@max_reports_per_message}"
    })
  end
end
