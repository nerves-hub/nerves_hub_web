defmodule NervesHubWeb.Live.Org.Users do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Invite
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.UserNotifier

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

    %{org: org, user: invited_by} = socket.assigns

    case Accounts.add_or_invite_to_org(invite_params, org, invited_by) do
      {:ok, %Invite{} = invite} ->
        invite_url = url(~p"/invite/#{invite.token}")

        _ = UserNotifier.deliver_user_invite(invite.email, org, invited_by, invite_url)
        _ = UserNotifier.deliver_all_tell_org_user_invited(org, invited_by, invite.email)

        socket
        |> put_flash(:info, "User has been invited")
        |> push_patch(to: ~p"/org/#{org}/settings/users")
        |> noreply()

      {:ok, %OrgUser{} = org_user} ->
        _ = UserNotifier.deliver_all_tell_org_user_added(org, invited_by, org_user.user)
        _ = UserNotifier.deliver_org_user_added(org, invited_by, org_user.user)

        socket
        |> put_flash(:info, "User has been added to #{org.name}")
        |> push_patch(to: ~p"/org/#{org}/settings/users")
        |> noreply()

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

    case Accounts.change_org_user_role(socket.assigns.membership, role) do
      {:ok, _org_user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Role updated")
         |> push_patch(to: ~p"/org/#{socket.assigns.org}/settings/users")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Error updating role")}
    end
  end

  def handle_event("delete_org_user", %{"user_id" => user_id}, socket) do
    authorized!(:"org_user:delete", socket.assigns.org_user)

    %{org: org, user: user} = socket.assigns

    {:ok, user_to_remove} = Accounts.get_user(user_id)

    case Accounts.remove_org_user(org, user_to_remove) do
      :ok ->
        _ = UserNotifier.deliver_all_tell_org_user_removed(org, user, user_to_remove)

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
