defmodule NervesHubWeb.Live.Org.Users do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Accounts
  alias NervesHub.Accounts.{Invite, Org, OrgUser}
  alias NervesHub.Accounts.SwooshEmail
  alias NervesHub.SwooshMailer
  alias NervesHubWeb.Components.Utils

  embed_templates("user_templates/*")

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> org_users()
    |> org_invites()
    |> page_title("Users - #{socket.assigns.org.name}")
    |> render_with(&users_template/1)
  end

  defp apply_action(socket, :invite, _params) do
    socket
    |> page_title("Invite User - #{socket.assigns.org.name}")
    |> assign(:form, to_form(Invite.changeset(%Invite{}, %{})))
    |> render_with(&invite_template/1)
  end

  defp apply_action(socket, :edit, %{"user_id" => user_id}) do
    {:ok, user} = Accounts.get_user(user_id)
    {:ok, org_user} = Accounts.get_org_user(socket.assigns.org, user)

    socket
    |> page_title("Edit User - #{socket.assigns.org.name}")
    |> assign(:membership, org_user)
    |> assign(:form, to_form(Org.change_user_role(org_user, %{})))
    |> render_with(&edit_user_template/1)
  end

  @impl Phoenix.LiveView
  def handle_event("send_invite", %{"invite" => invite_params}, socket) do
    authorized!(:"org_user:invite", socket.assigns.org_user)

    case Accounts.add_or_invite_to_org(invite_params, socket.assigns.org, socket.assigns.user) do
      {:ok, %Invite{} = invite} ->
        _ =
          SwooshEmail.invite(invite, socket.assigns.org, socket.assigns.user)
          |> SwooshMailer.deliver()

        {:noreply,
         socket
         |> put_flash(:info, "User has been invited")
         |> push_patch(to: ~p"/org/#{socket.assigns.org.name}/settings/users")}

      {:ok, %OrgUser{}} ->
        _ =
          SwooshEmail.org_user_created(
            invite_params["email"],
            socket.assigns.org,
            socket.assigns.user
          )
          |> SwooshMailer.deliver()

        {:noreply,
         socket
         |> put_flash(:info, "User has been added to #{socket.assigns.org.name}")
         |> push_patch(to: ~p"/org/#{socket.assigns.org.name}/settings/users")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("rescind_invite", %{"invite_token" => invite_token}, socket) do
    authorized!(:"org_user:invite:rescind", socket.assigns.org_user)

    case Accounts.delete_invite(socket.assigns.org, invite_token) do
      {:ok, _} ->
        {:noreply,
         socket
         |> org_invites()
         |> put_flash(:info, "Invite rescinded")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> org_invites()
         |> put_flash(:error, "Invite couldn't be rescinded as the invite has been accepted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Invite failed to rescind")}
    end
  end

  def handle_event("update-org-user", %{"org_user" => params}, socket) do
    authorized!(:"org_user:update", socket.assigns.org_user)

    {:ok, role} = Map.fetch(params, "role")

    with {:ok, _org_user} <- Accounts.change_org_user_role(socket.assigns.membership, role) do
      {:noreply,
       socket
       |> put_flash(:info, "Role updated")
       |> push_patch(to: ~p"/org/#{socket.assigns.org.name}/settings/users")}
    else
      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Error updating role")}
    end
  end

  def handle_event("delete_org_user", %{"user_id" => user_id}, socket) do
    authorized!(:"org_user:delete", socket.assigns.org_user)

    {:ok, user} = Accounts.get_user(user_id)

    case Accounts.remove_org_user(socket.assigns.org, user) do
      :ok ->
        _ =
          SwooshEmail.tell_org_user_removed(
            socket.assigns.org,
            Accounts.get_org_users(socket.assigns.org),
            socket.assigns.user,
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
