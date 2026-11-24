# Channel the device is connected to
defmodule NervesHubWeb.ConsoleChannel do
  @moduledoc """
  The device's end of its console: what the device prints goes up to whoever
  has the console open, and what they type comes down.

  ## Files sent to the device

  A file arrives as `file-data/start`, then `file-data` chunks, then
  `file-data/stop`. The device saves each chunk before it reads anything after
  it, typing included, so the console stops answering until the file is saved.

  A device whose console is 2.1.0 or later can say how that's going. This
  channel asks it to, by adding `"ack" => true` to `file-data/start`, and the
  device answers with `file-data/ack` after each chunk it saves (with the bytes
  saved so far), then `file-data/saved` once the file is complete, or
  `file-data/error` if it couldn't write it. They go up to the user's console
  like everything else, and `file_acks` in the metadata tells the page to
  expect them.

  Only this channel asks, never the page, so a device is only asked by a
  channel that handles the answers. An older channel never asks, and the page
  falls back to typing a character and deleting it, and waiting for the echo.
  """
  use Phoenix.Channel

  alias NervesHub.Consoles.PubSub
  alias NervesHubWeb.Channels.Scrollback
  alias Phoenix.Socket.Broadcast

  require Logger

  def join("console", payload, socket) do
    send(self(), {:after_join, payload})

    {:ok, assign(socket, scrollback: Scrollback.new(), file_acks?: false)}
  end

  def terminate(_, _socket) do
    {:shutdown, :closed}
  end

  def handle_in("up", payload, socket) do
    scrollback = Scrollback.append(socket.assigns.scrollback, payload["data"])
    socket = assign(socket, :scrollback, scrollback)

    PubSub.broadcast_to_user_console(device_id(socket), "up", payload)

    {:noreply, socket}
  end

  def handle_in("file-data/start", payload, socket) do
    PubSub.broadcast_to_user_console(device_id(socket), "file-data/start", payload)

    {:noreply, socket}
  end

  def handle_in("file-data", payload, socket) do
    PubSub.broadcast_to_user_console(device_id(socket), "file-data", payload)

    {:noreply, socket}
  end

  def handle_in("file-data/stop", payload, socket) do
    PubSub.broadcast_to_user_console(device_id(socket), "file-data/stop", payload)

    {:noreply, socket}
  end

  # How a file sent to the device is going, when this channel asked.
  def handle_in(event, payload, socket) when event in ["file-data/ack", "file-data/saved", "file-data/error"] do
    PubSub.broadcast_to_user_console(device_id(socket), event, payload)

    {:noreply, socket}
  end

  # A newer device can send something this channel doesn't know yet. Dropped,
  # rather than taking the console down with it.
  def handle_in(event, _payload, socket) do
    Logger.debug("Ignoring console event the server doesn't know: #{inspect(event)}")

    {:noreply, socket}
  end

  def handle_info({:after_join, payload}, socket) do
    socket =
      socket
      |> assign(:version, payload["console_version"])
      |> assign(:file_acks?, file_acks?(payload["console_version"]))

    # all devices are lumped into a `console` topic (the name used in join/3)
    # this can be a security issue as pubsub messages can be sent to all connected devices
    # additionally, this topic isn't needed or used, so we can unsubscribe from it
    socket.endpoint.unsubscribe("console")

    :ok = PubSub.subscribe_console(device_id(socket))

    PubSub.broadcast_console_joined(device_id(socket))

    {:noreply, socket}
  end

  # A page asking whether this device has a console. Replying with our pid lets
  # it monitor us for as long as it shows one.
  def handle_info({:locate_console, from, ref}, socket) do
    send(from, {:console_located, ref, self()})

    {:noreply, socket}
  end

  # A user console opening. Our pid is where it sends input from now on, rather
  # than broadcasting every keystroke to every node.
  def handle_info({:connect, pid}, socket) do
    metadata = %{version: socket.assigns.version, file_acks: socket.assigns.file_acks?}
    send(pid, {:metadata, self(), metadata})

    send(pid, {:cache, Scrollback.text(socket.assigns.scrollback)})

    {:noreply, socket}
  end

  def handle_info(%Broadcast{event: "file-data/start", payload: payload}, socket) do
    push(socket, "file-data/start", ask_for_acks(payload, socket.assigns.file_acks?))
    {:noreply, socket}
  end

  def handle_info(%Broadcast{payload: payload, event: event}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  defp device_id(socket), do: socket.assigns.device_info.device_id

  # Only this channel decides, so a page can't ask a device for answers that
  # an older channel would crash on.
  defp ask_for_acks(payload, true), do: Map.put(payload, "ack", true)
  defp ask_for_acks(payload, false), do: Map.delete(payload, "ack")

  # A console from 2.1.0 on says how a file it's sent is going, when asked.
  defp file_acks?(version) when is_binary(version) do
    case Version.parse(version) do
      {:ok, version} -> Version.compare(version, "2.1.0") != :lt
      :error -> false
    end
  end

  defp file_acks?(_version), do: false
end
