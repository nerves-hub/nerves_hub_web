defmodule NervesHubWeb.Mounts.AccountAuth do
  import Phoenix.Component
  import Phoenix.LiveView

  alias NervesHub.Accounts

  def on_mount(_, _, %{"auth_user_id" => user_id} = _session, socket) do
    socket =
      assign_new(socket, :user, fn ->
        {:ok, user} = Accounts.get_user_with_all_orgs_and_products(user_id)
        user
      end)

    if socket.assigns.user do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/login")}
    end
  end

  def on_mount(_, _, _session, socket) do
    {:halt, redirect(socket, to: "/login")}
  end
end
