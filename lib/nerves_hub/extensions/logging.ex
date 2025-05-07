defmodule NervesHub.Extensions.Logging do
  @behaviour NervesHub.Extensions

  alias NervesHub.Devices.LogLines
  alias NervesHub.RateLimit.LogLines, as: RateLimit

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
    # 5 tokens per second, max capacity of 10
    _ =
      case RateLimit.hit("device_#{device.id}", 5, 10, 1) do
        {:allow, _} ->
          LogLines.create!(device, log_line)

        {:deny, _} ->
          :noop
      end

    {:noreply, socket}
  end

  @impl NervesHub.Extensions
  def handle_info(_, socket) do
    {:noreply, socket}
  end
end
