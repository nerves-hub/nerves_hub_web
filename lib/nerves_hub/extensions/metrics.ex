defmodule NervesHub.Extensions.Metrics do
  @moduledoc """
  Numbers a device measures about itself, and nothing else.

  Version 0.1.0, batched from the start:

      server -> device   metrics:check   %{}
      device -> server   metrics:report  %{"reports" => [
                           %{"timestamp" => "2026-09-02T11:04:00Z",
                             "metrics" => %{"cpu_temp" => 41.2, "load_1min" => 0.4}},
                           ..
                         ]}

  ## Why this is not the health extension

  `NervesHub.Extensions.Health` carries metrics, metadata and alarms in one
  report, so a device sending metrics every minute also sends its firmware
  metadata every minute -- a blob that changes when the device is updated and
  at no other time. On a fleet, most of what health costs is the part that
  never changes.

  Splitting the numbers out lets the two run at their own pace. A device that
  attaches both should report health rarely, because that is how often what
  health carries actually changes. See `docs/metrics.md` for the contract, and
  `docs/extensions_protocol.md` for the handshake around it.

  Health goes on accepting metrics on 0.0.1. Every device in the field speaks
  it, and both paths end at `NervesHub.Devices.Metrics.record/3`, so what a
  report may carry is settled in one place rather than one per extension.

  ## Why it is batched

  A device that samples every ten seconds and reports every ten minutes gets to
  keep all sixty readings, and a device that loses its connection gets to keep
  what it measured while it was gone. Neither is possible if a message can only
  carry the instant it was sent, which is the mistake
  `NervesHub.Extensions.Logging.Batched` exists to correct and not one worth
  repeating.

  That is also why the readings are timestamped by the device. Everything else
  here is server-timestamped, because the platform saw it happen; these the
  platform did not see. A device whose clock has not caught up with NTP is the
  cost, and a day of skew either way is what is allowed before a reading is
  treated as unreadable rather than merely late.

  ## Pace

  Set by the platform, exactly as `Health` sets it and for the same reason: one
  timer per connection, so however many people have the device's page open, the
  device is asked once.

    * `:idle` -- nobody is looking. Report every `interval_minutes` (fifteen by
      default), the first one offset so a fleet does not answer in unison; see
      `NervesHub.Extensions.Jitter`.
    * `:watched` -- at least one device Show LiveView is open. Report every
      `ui_polling_seconds` (a minute by default).
  """

  @behaviour NervesHub.Extensions

  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Metrics, as: Store
  alias NervesHub.Extensions.Jitter
  alias NervesHub.Extensions.PubSub
  alias NervesHub.Extensions.State
  alias NervesHub.RateLimit.Metrics, as: RateLimit

  require Logger

  @default_interval_minutes 15
  @default_ui_polling_seconds 60

  @max_reports_per_message 60
  @max_clock_skew_hours 24

  # One message per second, with a little burst for a device catching up after a
  # reconnect. Its own bucket rather than a share of logging's or error
  # reports': a device in trouble produces all three at once, and the moment
  # they matter is the wrong moment for them to starve each other.
  @rate_limit_tokens_per_sec 1
  @rate_limit_max_capacity 5
  @rate_limit_token_cost 1

  @doc "How many reports one message may carry."
  def max_reports_per_message(), do: @max_reports_per_message

  @doc "How far a reported timestamp may be from the platform's clock."
  def max_clock_skew_hours(), do: @max_clock_skew_hours

  @impl NervesHub.Extensions
  def description() do
    """
    Reporting of device metrics on their own, without the metadata and alarms the Health extension carries.
    """
  end

  @impl NervesHub.Extensions
  def enabled?() do
    Application.get_env(:nerves_hub, :analytics_enabled)
  end

  @impl NervesHub.Extensions
  def attach(state) do
    mode = current_mode(state)

    {State.assign(state, :mode, mode),
     [{:group_join, PubSub.watch_key(device_id(state), :metrics)}, {:tick, :check}, timer(mode)]}
  end

  @impl NervesHub.Extensions
  def detach(state) do
    {State.assign(state, :mode, nil),
     [{:cancel_timer, :check}, {:group_leave, PubSub.watch_key(device_id(state), :metrics)}]}
  end

  @impl NervesHub.Extensions
  def handle_in("report", %{"reports" => []}, state) do
    # Nothing to store, and nothing charged for it. The budget is for the second
    # a device does have something to say.
    {state, []}
  end

  def handle_in("report", %{"reports" => reports}, state) when is_list(reports) do
    if allow?(state.device_info) do
      reports
      |> Enum.take(@max_reports_per_message)
      |> Enum.each(&record(state.device_info, &1))

      # Whoever is watching the device's page hears there are fresh numbers,
      # exactly as a health report announces itself. Costless when nobody is
      # watching — see `NervesHub.Extensions.PubSub.broadcast_report/3`.
      :ok = PubSub.broadcast_report(device_id(state), "metrics_report", %{})
    end

    {state, []}
  end

  # A device on 0.1.0 sends batches. Anything else is a client that declared a
  # version it does not speak, which is worth a log line and not worth a crash.
  def handle_in("report", payload, state) do
    Logger.warning(
      "device #{state.device_info.device_id} declared metrics 0.1.0 and sent #{inspect(payload, limit: 5)}"
    )

    {state, []}
  end

  @impl NervesHub.Extensions
  def handle_info(:check, state) do
    {state, effects} = reconsider(state)

    {state, [{:push, "metrics:check", %{}} | effects]}
  end

  # A device Show LiveView has opened on this device. Announced rather than
  # discovered, for the reason `NervesHub.Extensions.PubSub.watch/2` gives.
  def handle_info(:watching, state) do
    if State.get(state, :mode) == :watched do
      {state, []}
    else
      {State.assign(state, :mode, :watched), [{:tick, :check}, timer(:watched)]}
    end
  end

  def handle_info(_msg, state), do: {state, []}

  @doc """
  Whether this device may send now.

  One token per message, whatever the message carries. A message of sixty
  readings costs what a message of one costs, which is the point of batching --
  charging per reading would push a device towards sending more often.
  """
  @spec allow?(DeviceInfo.t()) :: boolean()
  def allow?(%DeviceInfo{} = device_info) do
    case RateLimit.hit(
           "metrics_device_#{device_info.device_id}",
           @rate_limit_tokens_per_sec,
           @rate_limit_max_capacity,
           @rate_limit_token_cost
         ) do
      {:allow, _count} -> true
      {:deny, _ms} -> false
    end
  end

  defp record(device_info, %{"metrics" => metrics} = report) when is_map(metrics) do
    case timestamp(report) do
      {:ok, timestamp} ->
        {:ok, _stored} = Store.record(device_info, metrics, timestamp)
        :ok

      :error ->
        :ok
    end
  end

  # A report with no metrics map, or one that is not a map. Skipped rather than
  # failing its neighbours: a device that gets one report wrong should not lose
  # the rest of the batch.
  defp record(_device_info, _report), do: :ok

  # A reading is only worth what its timestamp is worth. A device whose clock
  # has not caught up with NTP yet would otherwise write a chart that stretches
  # to 1970 or into next year, and the reading it names is unrecoverable either
  # way -- there is no telling how late it actually is.
  defp timestamp(%{"timestamp" => timestamp}) when is_binary(timestamp) do
    with {:ok, parsed, _offset} <- DateTime.from_iso8601(timestamp),
         true <- plausible?(parsed) do
      {:ok, parsed}
    else
      _ -> :error
    end
  end

  defp timestamp(_report), do: :error

  # Compared in seconds rather than hours: `DateTime.diff/3` truncates, so an
  # hours comparison would wave through anything under twenty-five.
  defp plausible?(timestamp) do
    abs(DateTime.diff(timestamp, DateTime.utc_now(), :second)) <= @max_clock_skew_hours * 3600
  end

  defp reconsider(state) do
    mode = current_mode(state)

    if mode == State.get(state, :mode) do
      {state, []}
    else
      {State.assign(state, :mode, mode), [timer(mode)]}
    end
  end

  defp current_mode(state) do
    if PubSub.watched?(device_id(state), :metrics), do: :watched, else: :idle
  end

  defp timer(:watched) do
    {:start_timer, :check, to_timeout(second: ui_polling_seconds())}
  end

  defp timer(:idle) do
    interval = to_timeout(minute: interval_minutes())

    {:start_timer, :check, Jitter.start_delay(interval), interval}
  end

  defp device_id(state), do: state.device_info.device_id

  defp interval_minutes() do
    case config([:metrics, :interval_minutes]) do
      i when is_integer(i) and i > 0 -> i
      _ -> @default_interval_minutes
    end
  end

  defp ui_polling_seconds() do
    case config([:metrics, :ui_polling_seconds]) do
      i when is_integer(i) and i > 0 -> i
      _ -> @default_ui_polling_seconds
    end
  end

  defp config(path) do
    :nerves_hub
    |> Application.get_env(:extension_config, [])
    |> get_in(path)
  end
end
