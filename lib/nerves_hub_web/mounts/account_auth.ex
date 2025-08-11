defmodule NervesHubWeb.Mounts.AccountAuth do
  import Phoenix.Component
  import Phoenix.LiveView

  alias NervesHub.Accounts

  def on_mount(_, _, %{"user_token" => user_token} = _session, socket) do
    socket =
      assign_new(socket, :user, fn ->
        user = Accounts.get_user_by_session_token(user_token)

        case user && Accounts.get_user_with_all_orgs_and_products(user.id) do
          {:ok, full_user} -> full_user
          _ -> nil
        end
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
