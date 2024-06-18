defmodule NervesHubWeb.Live.Org.Users do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Accounts

  def mount(_params, _session, socket) do
    socket =
      socket
      |> org_users()
      |> org_invites()
      |> assign(:page_title, "#{socket.assigns.org.name} - Users")

    {:ok, socket}
  end

  def handle_event("rescind_invite", %{"invite_token" => invite_token}, socket) do
    authorized!(:rescind_invite, socket.assigns.org_user)

    case Accounts.delete_invite(socket.assigns.org, invite_token) do
      {:ok, _} ->
        {:noreply,
         socket
         |> org_invites()
         |> put_flash(:info, "Invite rescinded")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Invite failed to rescind")}
    end
  end

  def handle_event("delete_org_user", %{"user_id" => user_id}, socket) do
    authorized!(:delete_org_user, socket.assigns.org_user)

    {:ok, user} = Accounts.get_user(user_id)

    case Accounts.remove_org_user(socket.assigns.org, user) do
      :ok ->
        SwooshEmail.tell_org_user_removed(
          socket.assigns.org,
          Accounts.get_org_users(socket.assigns.org),
          socket.user.username,
          user
        )
        |> SwooshMailer.deliver()

        {:noreply,
         socket
         |> org_users()
         |> put_flash(:info, "User removed")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not remove user")}
    end
  end

  defp org_users(socket) do
    assign(socket, :org_users, Accounts.get_org_users(socket.assigns.org))
  end

  defp org_invites(socket) do
    assign(socket, :invites, Accounts.get_invites_for_org(socket.assigns.org))
  end
end
