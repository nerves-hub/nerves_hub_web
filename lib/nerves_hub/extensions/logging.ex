defmodule NervesHub.Extensions.Logging do
  @behaviour NervesHub.Extensions

  alias NervesHub.Devices.LogLines

  @impl NervesHub.Extensions
  def description() do
    """
    Send and store device logs on NervesHub.
    """
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
  def handle_in("logging:send", log_line, socket) do
    inserted_log_line = LogLines.create!(socket.assigns.device, log_line)

    _ =
      Phoenix.Channel.Server.broadcast(
        NervesHub.PubSub,
        "device:#{socket.assigns.device.identifier}:internal",
        "logs:received",
        inserted_log_line
      )

    {:noreply, socket}
  end

  @impl NervesHub.Extensions
  def handle_info(_, socket) do
    {:noreply, socket}
  end
end
