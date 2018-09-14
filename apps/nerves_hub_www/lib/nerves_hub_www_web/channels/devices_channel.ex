defmodule NervesHubWWWWeb.DevicesChannel do
  use NervesHubWWWWeb, :channel
  alias NervesHubCore.Accounts
  alias NervesHubDevice.Presence

  def join("devices:" <> org_id, _payload, socket) do
    if authorized?(socket.assigns.auth_user_id, String.to_integer(org_id)) do
      send(self(), :after_join)
      {:ok, assign(socket, :org_id, org_id)}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def handle_info(:after_join, socket) do
    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  defp authorized?(user_id, org_id) do
    Accounts.user_in_org?(user_id, org_id)
  end
end
