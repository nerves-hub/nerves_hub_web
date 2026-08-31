defmodule NervesHub.Extensions.Health do
  @moduledoc """
  Device metrics, metadata and alarms, reported on a pace this module sets.

  The platform decides when a device reports, and nothing else asks: a `check`
  goes out on one timer per connection, so however many people have the device's
  page open, the device is asked once. It used to be the other way around -- the
  Show LiveView ran its own timer and requested a check directly, on top of this
  one, once per open page -- which meant two people looking at a device asked it
  for three reports a minute between them, none of them aligned.

  The pace has two settings, and which one is in force is the `:mode` assign:

    * `:idle` -- nobody is looking. Report every `interval_minutes` (an hour by
      default), the first one offset so a fleet does not answer in unison; see
      `NervesHub.Extensions.Jitter`.
    * `:watched` -- at least one device Show LiveView is open. Report every
      `ui_polling_seconds` (a minute by default), because somebody is reading
      the numbers and a stale reading is the thing they would notice.

  Both transitions come from `NervesHub.Extensions.PubSub`, and they are not
  symmetric: opening a page announces itself, closing one cannot. See
  `NervesHub.Extensions.PubSub.watch_health/1` for why each direction works the
  way it does.
  """

  @behaviour NervesHub.Extensions

  alias NervesHub.Devices.Health
  alias NervesHub.Devices.HealthStatus
  alias NervesHub.Devices.Metrics
  alias NervesHub.Extensions.Jitter
  alias NervesHub.Extensions.PubSub
  alias NervesHub.Extensions.State
  alias NervesHub.Helpers.Logging

  require Logger

  @default_interval_minutes 60
  @default_ui_polling_seconds 60

  @impl NervesHub.Extensions
  def description() do
    """
    Reporting of fundamental device metrics, metadata, alarms and more.
    """
  end

  @impl NervesHub.Extensions
  def enabled?() do
    true
  end

  @impl NervesHub.Extensions
  def attach(state) do
    # Ask for a report immediately, then on an interval. The tick is delivered
    # before the first timer fires, which preserves the previous ordering.
    #
    # The pace is settled here rather than starting slow and being told,
    # because a page that was already open when the device connected has
    # nothing left to announce -- its join happened before there was anything
    # to announce it to.
    mode = current_mode(state)

    {State.assign(state, :mode, mode),
     [{:group_join, PubSub.health_key(device_id(state))}, {:tick, :check}, timer(mode)]}
  end

  @impl NervesHub.Extensions
  def detach(state) do
    {State.assign(state, :mode, nil), [{:cancel_timer, :check}, {:group_leave, PubSub.health_key(device_id(state))}]}
  end

  @impl NervesHub.Extensions
  def handle_in("report", %{"value" => device_report}, state) do
    device_info = state.device_info

    # Get metrics from health report to store in metrics table and calculate status
    metrics = device_report["metrics"] || %{}

    # Get device status together with reasons, if any.
    {status, reasons} =
      case HealthStatus.calculate_metrics_status(metrics) do
        {status, reasons} -> {status, reasons}
        status -> {status, nil}
      end

    device_health = %{
      "device_id" => device_info.device_id,
      "data" => device_report,
      "status" => status,
      "status_reasons" => reasons
    }

    with {:health_report, {:ok, _}} <-
           {:health_report, Health.save_device_health(device_health)},
         {:metrics_report, {:ok, _}} <-
           {:metrics_report, Metrics.save_metrics(device_info.device_id, metrics)} do
      :ok = PubSub.broadcast_report(device_info.device_id, "health_check_report", %{})
    else
      {:health_report, {:error, err}} ->
        Logger.warning("Failed to save health check data: #{inspect(err)}")

        Logging.log_to_sentry(
          device_info,
          "[DeviceChannel] Failed to save health check data."
        )

      {:metrics_report, :error} ->
        Logger.warning("Failed to save metrics report")

        Logging.log_to_sentry(
          device_info,
          "[DeviceChannel] Failed to save metrics report."
        )
    end

    {state, []}
  end

  @impl NervesHub.Extensions
  def handle_info(:check, state) do
    # A check is also when the pace is reconsidered, which is what makes the
    # slowdown work without anything having to announce a page closing: while
    # watched, this runs every minute, so the last person leaving costs the
    # device one extra report. Doing it here rather than on a monitor of the
    # watchers group also means the read is never racing the join it is reading
    # -- by now it has long since replicated.
    {state, effects} = reconsider(state)

    {state, [{:push, "health:check", %{}} | effects]}
  end

  # A device Show LiveView has opened on this device. Announced rather than
  # discovered so that speeding up does not wait on the join replicating to
  # whichever node this is running on; see
  # `NervesHub.Extensions.PubSub.watch_health/1`.
  def handle_info(:watching, state) do
    if State.get(state, :mode) == :watched do
      {state, []}
    else
      # Somebody has just opened the page and is looking at numbers taken up to
      # an hour ago, so this asks straight away rather than in a minute.
      {State.assign(state, :mode, :watched), [{:tick, :check}, timer(:watched)]}
    end
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
    if PubSub.health_watched?(device_id(state)), do: :watched, else: :idle
  end

  # Replaces whatever is armed under `:check`; see `NervesHubWeb.Channels.Effects`.
  defp timer(:watched) do
    {:start_timer, :check, to_timeout(second: ui_polling_seconds())}
  end

  defp timer(:idle) do
    interval = to_timeout(minute: health_interval_minutes())

    {:start_timer, :check, Jitter.start_delay(interval), interval}
  end

  defp device_id(state), do: state.device_info.device_id

  defp health_interval_minutes() do
    case config([:health, :interval_minutes]) do
      i when is_integer(i) and i > 0 -> i
      _ -> @default_interval_minutes
    end
  end

  defp ui_polling_seconds() do
    case config([:health, :ui_polling_seconds]) do
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
