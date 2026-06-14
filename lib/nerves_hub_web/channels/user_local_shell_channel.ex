defmodule NervesHubWeb.UserLocalShellChannel do
  use NervesHubWeb, :channel

  alias NervesHub.Accounts
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.Scope
  alias NervesHub.Devices
  alias NervesHub.Extensions.LocalShell
  alias NervesHubWeb.Helpers.Authorization
  alias Phoenix.Socket.Broadcast

  def join("user:local_shell:identifier-" <> identifier, _, socket) do
    if device = authorized?(socket.assigns.user, identifier) do
      :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, "user:local_shell:#{device.id}")

      topic = "device:#{device.id}:extensions"
      message = {LocalShell, {:connect, self()}}
      _ = Phoenix.PubSub.broadcast(NervesHub.PubSub, topic, message)

      {:ok, assign(socket, :device_id, device.id)}
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

  def handle_info(%Broadcast{event: "output", payload: payload}, socket) do
    push(socket, "output", payload)
    {:noreply, socket}
  end

  def handle_info({:cache, lines}, socket) do
    push(socket, "output", %{data: lines})
    {:noreply, socket}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp authorized?(user, identifier) do
    scope = Scope.for_user(user)

    with {:ok, device} <- Devices.get_by_identifier(scope, identifier),
         %OrgUser{} = org_user <- Accounts.find_org_user_with_device(user, device.id),
         true <- Authorization.authorized?(:"device:console", org_user) do
      device
    else
      _ ->
        nil
    end
  end
end
