defmodule NervesHubWeb.DeviceLive.Console do
  use NervesHubWeb, :live_view

  require Logger

  alias NervesHubDevice.Presence
  alias NervesHub.{Accounts, Devices, Products}
  alias Phoenix.Socket.Broadcast

  @theme AnsiToHTML.Theme.new(container: :none, "\e[22m": {:text, []})

  def render(assigns) do
    NervesHubWeb.DeviceView.render("console_live.html", assigns)
  end

  def mount(
        _params,
        %{
          "auth_user_id" => user_id,
          "org_id" => org_id,
          "product_id" => product_id,
          "device_id" => device_id
        },
        socket
      ) do
    socket =
      socket
      |> assign_new(:user, fn -> Accounts.get_user!(user_id) end)
      |> assign_new(:org, fn -> Accounts.get_org!(org_id) end)
      |> assign_new(:product, fn -> Products.get_product!(product_id) end)
      |> assign_new(:device, fn ->
        Devices.get_device_by_product(device_id, product_id, org_id)
      end)

    if connected?(socket) do
      socket.endpoint.subscribe(console_topic(socket.assigns.device))
    end

    user = Repo.preload(socket.assigns.user, :org_users)
    org_user = Enum.find(user.org_users, %{role: :read}, &(&1.org_id == socket.assigns.org.id))

    socket
    |> assign(:active_line, "iex(#{user.username})> ")
    |> assign(:lines, ["NervesHub IEx Live"])
    |> assign(:user_role, org_user.role)
    |> init_iex()
  rescue
    exception ->
      Logger.error(Exception.format(:error, exception, __STACKTRACE__))
      socket_error(socket, live_view_error(exception))
  end

  # Catch-all to handle when LV sessions change.
  # Typically this is after a deploy when the
  # session structure in the module has changed
  # for mount/3
  def mount(_, _session, socket) do
    socket_error(socket, live_view_error(:update))
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
    #
    # Also, IO :put_chars has to explicitly add newline characters for the
    # terminal to break each line. However, rendering each line in HTML
    # already formats each "line" as an element, which already gets rendered
    # on a newline. So we trim any trailing whitespace or newline here to
    # prevent line bloat.
    line =
      IO.iodata_to_binary(line)
      |> String.trim_trailing()
      |> AnsiToHTML.generate_phoenix_html(@theme)

    new_lines = List.insert_at(lines, -1, line)
    {:noreply, assign(socket, :lines, new_lines)}
  end

  def handle_info(
        %Broadcast{event: "get_line", payload: %{"data" => line}},
        %{assigns: %{user: %{username: username}}} = socket
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

  defp init_iex(
         %{
           assigns: %{
             org: org,
             product: product,
             device: device,
             user_role: :admin
           }
         } = socket
       ) do
    case Presence.find(device) do
      %{console_available: true} ->
        socket.endpoint.broadcast_from!(self(), console_topic(socket), "init", %{})
        {:ok, socket}

      _ ->
        socket =
          socket
          |> put_flash(:error, "Device not configured to support remote IEx console")
          |> redirect(
            to:
              Routes.device_path(
                socket,
                :show,
                org.name,
                product.name,
                device.identifier
              )
          )

        {:ok, socket}
    end
  end

  defp init_iex(socket) do
    {:ok, socket}
  end
end
