defmodule NervesHubWeb.Mounts.FetchOrgUser do
  import Phoenix.Component

  alias NervesHub.Accounts

  def on_mount(_, _, _, socket) do
    socket =
      assign_new(socket, :org_user, fn ->
        {:ok, org_user} = Accounts.get_org_user(socket.assigns.org, socket.assigns.user)
        org_user
      end)

    {:cont, socket}
  end
end
