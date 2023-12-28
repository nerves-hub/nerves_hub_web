defmodule NervesHubWeb.Mounts.AccountAuth do
  import Phoenix.Component
  import Phoenix.LiveView

  alias NervesHub.Accounts

  def on_mount(_, _, %{"auth_user_id" => user_id} = _session, socket) do
    case Accounts.get_user_with_all_orgs_and_products(user_id) do
      {:ok, user} ->
        socket =
          socket
          |> assign(:user, user)
          |> assign(:orgs, user.orgs)

        {:cont, socket}

      _ ->
        {:halt, redirect(socket, to: "/login")}
    end
  end

  def on_mount(_, _, _session, socket) do
    {:halt, redirect(socket, to: "/login")}
  end
end
