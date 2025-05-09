defmodule NervesHub.Extensions.Logging do
  @behaviour NervesHub.Extensions

  alias NervesHub.Devices.LogLines
  alias NervesHub.RateLimit.LogLines, as: RateLimit

  @rate_limit_tokens_per_sec 5
  @rate_limit_max_capacity 10
  @rate_limit_token_cost 1

  @impl NervesHub.Extensions
  def description() do
    """
    Send and store device logs on NervesHub.
    """
  end

  @impl NervesHub.Extensions
  def enabled?() do
    Application.get_env(:nerves_hub, :analytics_enabled)
  end

  @impl NervesHub.Extensions
  def attach(socket) do
    {:noreply, socket}
  end

  @impl NervesHub.Extensions
  def detach(socket) do
    {:noreply, socket}
  end

  @impl NervesHub.Extensions
  def handle_in("logging:send", log_line, %{assigns: %{device: device}} = socket) do
    case RateLimit.hit(
           "device_#{device.id}",
           @rate_limit_tokens_per_sec,
           @rate_limit_max_capacity,
           @rate_limit_token_cost
         ) do
      {:allow, _} ->
        schedule_create(device, log_line)

      {:deny, _} ->
        :noop
    end

    {:noreply, socket}
  end

  @impl NervesHub.Extensions
  def handle_info(_, socket) do
    {:noreply, socket}
  end

  defp schedule_create(device, log_line) do
    _ =
      Task.Supervisor.async(
        {:via, PartitionSupervisor, {NervesHub.AnalyticsEventsProcessing, self()}},
        fn -> LogLines.create!(device, log_line) end
      )

    :noop
  end
end
