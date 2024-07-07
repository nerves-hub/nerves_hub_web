defmodule NervesHubWeb.Mounts.FetchOrgUser do
  import Phoenix.Component

  alias NervesHub.Accounts

  def on_mount(_, _, _, socket) do
    socket =
      assign_new(socket, :org_user, fn ->
        if socket.assigns[:product] do
          List.first(socket.assigns.product.org.org_users)
        else
          Accounts.get_org_user!(socket.assigns.org, socket.assigns.user)
        end
      end)

    {:cont, socket}
  end
end
