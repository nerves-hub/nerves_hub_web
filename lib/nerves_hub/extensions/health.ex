defmodule NervesHub.Extensions.Health do
  @behaviour NervesHub.Extensions

  alias NervesHub.Devices.DeviceMessages
  alias NervesHub.Devices.Health
  alias NervesHub.Devices.HealthStatus
  alias NervesHub.Devices.Metrics
  alias NervesHub.Extensions.Jitter
  alias NervesHub.Extensions.PubSub
  alias NervesHub.Helpers.Logging

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
    # Ask for a report immediately, then on an interval. The tick is delivered
    # before the first timer fires, which preserves the previous ordering.
    interval = to_timeout(minute: health_interval_minutes())

    {state, [{:tick, :check}, {:start_timer, :check, Jitter.start_delay(interval), interval}]}
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
    {state, [{:push, "health:check", %{}}]}
  end

  def request_health_check(device) do
    # Recorded here rather than in the wrapper; see `NervesHub.Extensions.PubSub`.
    :ok = DeviceMessages.record(device, :sent, :extensions, "health:check", %{})
    :ok = PubSub.broadcast_to_device(device.id, "health:check", %{})
  end

  defp health_interval_minutes() do
    extension_config = Application.get_env(:nerves_hub, :extension_config, [])

    case get_in(extension_config, [:health, :interval_minutes]) do
      i when is_integer(i) and i > 0 -> i
      _ -> @default_interval_minutes
    end
  end
end
