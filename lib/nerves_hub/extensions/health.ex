defmodule NervesHub.Extensions.Health do
  @behaviour NervesHub.Extensions

  alias NervesHub.Devices.Health
  alias NervesHub.Devices.HealthStatus
  alias NervesHub.Devices.Metrics
  alias NervesHub.Helpers.Logging
  alias Phoenix.Channel.Server, as: ChannelServer

  require Logger

  @default_interval_minutes 60

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
    interval = to_timeout(minute: health_interval_minutes())

    # Ask for a report immediately, then on an interval. The tick is delivered
    # before the first timer fires, which preserves the previous ordering.
    {state, [{:tick, :check}, {:start_timer, :check, interval}]}
  end

  @impl NervesHub.Extensions
  def detach(state) do
    {state, [{:cancel_timer, :check}]}
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
      :ok = internal_broadcast!(device_info.device_id, "health_check_report", %{})
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
    {state, [{:push, "health:check", %{}}]}
  end

  def request_health_check(device) do
    :ok = device_broadcast!(device.id, "health:check", %{})
  end

  defp health_interval_minutes() do
    extension_config = Application.get_env(:nerves_hub, :extension_config, [])

    case get_in(extension_config, [:health, :interval_minutes]) do
      i when is_integer(i) and i > 0 -> i
      _ -> @default_interval_minutes
    end
  end

  # Bound for the device: the extensions channel forwards everything on this
  # topic on to it.
  defp device_broadcast!(device_id, event, payload) do
    topic = "device:#{device_id}:extensions"

    ChannelServer.broadcast_from!(NervesHub.PubSub, self(), topic, event, payload)
  end

  # Bound for whoever is watching the device in the UI, and nothing else.
  #
  # This deliberately does not ride the device topic. Keeping it off the wire
  # there would depend on excluding `self()`, and `self()` is only the device's
  # connection while this runs in the same process as it — which is not
  # something this module gets to assume.
  defp internal_broadcast!(device_id, event, payload) do
    topic = "internal:device:#{device_id}"

    ChannelServer.broadcast!(NervesHub.PubSub, topic, event, payload)
  end
end
