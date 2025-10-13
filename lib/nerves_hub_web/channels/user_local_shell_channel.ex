defmodule NervesHubWeb.UserLocalShellChannel do
  use NervesHubWeb, :channel

  alias NervesHub.Accounts

  alias NervesHubWeb.Helpers.Authorization

  def join("user:local_shell:" <> device_id, _, socket) do
    if authorized?(socket.assigns.user, device_id) do
      topic = "device:#{device_id}:extensions"
      message = {NervesHub.Extensions.LocalShell, {:connect, self()}}
      _ = Phoenix.PubSub.broadcast(NervesHub.PubSub, topic, message)
      {:ok, assign(socket, :device_id, device_id)}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def handle_in("input", payload, socket) do
    # Key presses are coming in here raw
    # Send them to the device
    topic = "device:#{socket.assigns.device_id}:extensions"
    socket.endpoint.broadcast!(topic, "local_shell:shell_input", payload)
    {:noreply, socket}
  end

  def handle_in("window_size", payload, socket) do
    topic = "device:#{socket.assigns.device_id}:extensions"
    socket.endpoint.broadcast!(topic, "local_shell:window_size", payload)
    {:noreply, socket}
  end

  def handle_info({:cache, lines}, socket) do
    push(socket, "output", %{data: lines})
    {:noreply, socket}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp authorized?(user, device_id) do
    case Accounts.find_org_user_with_device(user, device_id) do
      nil ->
        false

      org_user ->
        Authorization.authorized?(:"device:extensions:local_shell", org_user)
    end
  end
end
