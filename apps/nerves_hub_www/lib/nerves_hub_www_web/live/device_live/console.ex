defmodule NervesHubWWWWeb.DeviceLive.Console do
  use NervesHubWWWWeb, :live_view

  alias NervesHubDevice.Presence
  alias NervesHubWebCore.{Accounts, Accounts.Org, Devices}
  alias Phoenix.Socket.Broadcast

  @theme AnsiToHTML.Theme.new(container: :none, "\e[22m": {:text, []})

  def render(assigns) do
    NervesHubWWWWeb.DeviceView.render("console.html", assigns)
  end

  def mount(
        %{auth_user_id: user_id, current_org_id: org_id, path_params: %{"id" => device_id}},
        socket
      ) do
    case Devices.get_device_by_org(%Org{id: org_id}, device_id) do
      {:ok, device} ->
        if connected?(socket) do
          socket.endpoint.subscribe(console_topic(device))
        end

        {:ok, user} = Accounts.get_user(user_id)
        user = Repo.preload(user, :org_users)
        org_user = Enum.find(user.org_users, %{role: :read}, &(&1.org_id == org_id))

        socket
        |> assign(:active_line, "iex(#{user.username})> ")
        |> assign(:device, device)
        |> assign(:lines, ["NervesHub IEx Live"])
        |> assign(:username, user.username)
        |> assign(:user_role, org_user.role)
        |> init_iex()

      {:error, :not_found} ->
        {:stop,
         socket
         |> put_flash(:error, "Device not found")
         |> redirect(to: "/devices")}
    end
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
    # Lines may come in as a list of characters and/or numbers to represent
    # a string. So call to_string here just to convert before attempting
    # any transposing to HTML which relies on strings.
    line =
      IO.iodata_to_binary(line)
      |> AnsiToHTML.generate_phoenix_html(@theme)

    new_lines = List.insert_at(lines, -1, line)
    {:noreply, assign(socket, :lines, new_lines)}
  end

  def handle_info(
        %Broadcast{event: "get_line", payload: %{"data" => line}},
        %{assigns: %{username: username}} = socket
      ) do
    line = String.replace(line, ~r/(iex).*(>)/, "\\1(#{username})\\2")
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

  defp console_topic(%{id: device_id}) do
    "console:#{device_id}"
  end

  defp init_iex(%{assigns: %{device: device, user_role: :admin}} = socket) do
    case Presence.find(device) do
      %{console_available: true} ->
        socket.endpoint.broadcast_from!(self(), console_topic(socket), "init", %{})
        {:ok, socket}

      _ ->
        socket =
          socket
          |> put_flash(:error, "Device not configured to support remote IEx console")
          |> redirect(to: "/devices/#{device.id}")

        {:stop, socket}
    end
  end

  defp init_iex(socket), do: {:ok, socket}
end
