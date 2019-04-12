defmodule NervesHubWWWWeb.DeviceLive.Console do
  use Phoenix.LiveView

  alias Phoenix.Socket.Broadcast

  @theme AnsiToHTML.Theme.new(container: :none)

  def render(assigns) do
    NervesHubWWWWeb.DeviceView.render("console.html", assigns)
  end

  def mount(session, socket) do
    if connected?(socket) do
      socket.endpoint.subscribe(console_topic(session))

      if session.user_role == :admin do
        socket.endpoint.broadcast_from!(self(), console_topic(session), "init", %{})
      end
    end

    socket =
      socket
      |> assign(:active_line, "iex (#{session.username})> ")
      |> assign(:device, session.device)
      |> assign(:lines, ["NervesHub IEx Live"])
      |> assign(:username, session.username)
      |> assign(:user_role, session.user_role)

    {:ok, socket}
  end

  def handle_event("init_console", _value, socket) do
    socket.endpoint.broadcast_from!(self(), console_topic(socket), "init", %{})
    {:noreply, socket}
  end

  # clear all the current input by typing and submitting "clear"
  def handle_event("iex_submit", %{"iex_input" => "clear"}, socket) do
    {:noreply, assign(socket, :lines, [])}
  end

  def handle_event(
        "iex_submit",
        %{"iex_input" => line},
        %{assigns: %{active_line: active, lines: lines, user_role: :admin}} = socket
      ) do
    new_lines = List.insert_at(lines, -1, active <> line)

    # Tell other Live sessions to add the submitted line
    socket.endpoint.broadcast_from!(self(), console_topic(socket), "add_line", %{
      data: active <> line
    })

    # Send the reply to the device
    socket.endpoint.broadcast_from!(self(), console_topic(socket), "io_reply", %{
      data: line,
      kind: "get_line"
    })

    {:noreply, assign(socket, :lines, new_lines)}
  end

  def handle_event("iex_submit", _value, socket) do
    {:noreply, put_flash(socket, :error, "User not authorized to submit IEx commands")}
  end

  def handle_info(%{event: "init_failure"}, socket) do
    {:noreply, put_flash(socket, :error, "Failed to start remote IEx")}
  end

  def handle_info(
        %Broadcast{event: "put_chars", payload: %{"data" => line}},
        %{assigns: %{lines: lines}} = socket
      ) do
    line = AnsiToHTML.generate_phoenix_html(line, @theme)
    new_lines = List.insert_at(lines, -1, line)
    {:noreply, assign(socket, :lines, new_lines)}
  end

  def handle_info(
        %Broadcast{event: "get_line", payload: %{"data" => line}},
        %{assigns: %{username: username}} = socket
      ) do
    line = String.replace(line, ~r/(iex\()\d+(\))/, "\\1#{username}\\2")
    {:noreply, assign(socket, :active_line, line)}
  end

  def handle_info(
        %Broadcast{event: "add_line", payload: %{data: line}},
        %{assigns: %{lines: lines}} = socket
      ) do
    new_lines = List.insert_at(lines, -1, line)
    {:noreply, assign(socket, :lines, new_lines)}
  end

  # Ignore unknown broadcasts
  # Specifically, this ignores cases where another session
  # broadcasts messages for the device like `io_reply`
  def handle_info(%Broadcast{}, socket) do
    {:noreply, socket}
  end

  defp console_topic(%{assigns: %{device: device}}) do
    "console:#{device.id}"
  end

  defp console_topic(%{device: device}) do
    "console:#{device.id}"
  end
end
