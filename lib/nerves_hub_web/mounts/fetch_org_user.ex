defmodule NervesHubWeb.Mounts.FetchOrgUser do
  import Phoenix.Component

  alias NervesHub.Accounts

  def on_mount(_, _, _, socket) do
    {:ok, org_user} = Accounts.get_org_user(socket.assigns.org, socket.assigns.user)

    {:cont, assign(socket, :org_user, org_user)}
  end
end
