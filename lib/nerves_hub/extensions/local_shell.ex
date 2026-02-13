defmodule NervesHub.Extensions.LocalShell do
  @behaviour NervesHub.Extensions

  import Phoenix.Socket, only: [assign: 3]

  @impl NervesHub.Extensions
  def description() do
    """
    Connect to the devices local shell.
    """
  end

  @impl NervesHub.Extensions
  def enabled?() do
    true
  end

  @impl NervesHub.Extensions
  def attach(socket) do
    Phoenix.Channel.push(socket, "local_shell:request_shell", %{})

    socket =
      socket
      |> assign(:current_line, "")
      |> assign(:buffer, CircularBuffer.new(1024))

    {:noreply, socket}
  end

  @impl NervesHub.Extensions
  def detach(socket) do
    socket =
      socket
      |> assign(:current_line, nil)
      |> assign(:buffer, nil)

    {:noreply, socket}
  end

  @impl NervesHub.Extensions
  def handle_in("shell_output", %{"data" => data}, socket) do
    current_line = socket.assigns.current_line <> data

    [current_line | lines] = Enum.reverse(String.split(current_line, "\n"))

    buffer =
      Enum.reduce(Enum.reverse(lines), socket.assigns.buffer, fn line, buffer ->
        CircularBuffer.insert(buffer, line <> "\n")
      end)

    socket =
      socket
      |> assign(:current_line, current_line)
      |> assign(:buffer, buffer)

    topic = "user:local_shell:#{socket.assigns.device.id}"

    socket.endpoint.broadcast!(topic, "output", %{data: data})

    {:noreply, socket}
  end

  def handle_info({:connect, pid}, socket) do
    lines = Enum.join(socket.assigns.buffer) <> socket.assigns.current_line

    send(pid, {:cache, lines})

    {:noreply, socket}
  end

  def handle_info({:active?, pid}, socket) do
    send(pid, :active)

    {:noreply, socket}
  end

  @impl NervesHub.Extensions
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end
end
