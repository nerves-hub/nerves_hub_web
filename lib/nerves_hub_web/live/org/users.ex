defmodule NervesHubWeb.Live.Org.Users do
  use NervesHubWeb, :live_view

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Invite
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.UserNotifier
  alias NervesHubWeb.Components.Utils
  alias NervesHubWeb.InviteLinks
  alias NervesHubWeb.Mounts.OrgCounts

  on_mount(OrgCounts)

  embed_templates("user_templates/*")

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :org, socket.assigns.current_scope.org)}
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
    |> sidebar_tab(:users)
    |> render_with(&users_template/1)
  end

  defp apply_action(socket, :invite, _params) do
    socket
    |> page_title("Invite User - #{socket.assigns.org.name}")
    |> assign(:form, to_form(Invite.changeset(%Invite{}, %{})))
    |> sidebar_tab(:users)
    |> render_with(&invite_template/1)
  end

  defp apply_action(socket, :edit, %{"user_id" => user_id}) do
    org_user = Accounts.get_org_user!(socket.assigns.current_scope, user_id)

    socket
    |> page_title("Edit User - #{socket.assigns.org.name}")
    |> assign(:membership, org_user)
    |> assign(:form, to_form(Org.change_user_role(org_user)))
    |> sidebar_tab(:users)
    |> render_with(&edit_user_template/1)
  end

  @impl Phoenix.LiveView
  def handle_event("send_invite", %{"invite" => invite_params}, socket) do
    %{org: org, current_scope: %{user: invited_by} = scope} = socket.assigns

    authorized!(:"org_user:invite", scope)

    case Accounts.invite(invite_params, org, invited_by) do
      {:ok, %Invite{} = invite} ->
        has_account? = match?({:ok, _user}, Accounts.get_user_by_email(invite.email))

        _ =
          UserNotifier.deliver_user_invite(invite.email, org, invited_by, InviteLinks.emailed_url(invite), has_account?)

        _ = UserNotifier.deliver_all_tell_org_user_invited(org, invited_by, invite.email)

        socket
        |> put_flash(:info, "User has been invited")
        |> push_patch(to: ~p"/org/#{org}/settings/users")
        |> noreply()

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("resend_invite", %{"invite_token" => invite_token}, socket) do
    %{org: org, current_scope: scope} = socket.assigns

    authorized!(:"org_user:invite:resend", scope)

    case Accounts.resend_invite(org, invite_token) do
      {:ok, invite} ->
        has_account? = match?({:ok, _user}, Accounts.get_user_by_email(invite.email))

        _ =
          UserNotifier.deliver_user_invite(
            invite.email,
            org,
            invite.invited_by,
            InviteLinks.emailed_url(invite),
            has_account?
          )

        socket
        |> org_invites()
        |> put_flash(:info, "Invite resent to #{invite.email}")
        |> noreply()

      {:error, reason} when is_atom(reason) ->
        socket
        |> org_invites()
        |> put_flash(:error, "Invite couldn't be resent as #{invite_unavailable(reason)}.")
        |> noreply()

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Invite failed to resend")}
    end
  end

  def handle_event("rescind_invite", %{"invite_token" => invite_token}, socket) do
    authorized!(:"org_user:invite:rescind", socket.assigns.current_scope)

    case Accounts.delete_invite(socket.assigns.org, invite_token) do
      {:ok, _} ->
        {:noreply,
         socket
         |> org_invites()
         |> put_flash(:info, "Invite rescinded")}

      {:error, reason} when is_atom(reason) ->
        {:noreply,
         socket
         |> org_invites()
         |> put_flash(:error, "Invite couldn't be rescinded as #{invite_unavailable(reason)}.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Invite failed to rescind")}
    end
  end

  def handle_event("update-org-user", %{"org_user" => params}, socket) do
    authorized!(:"org_user:update", socket.assigns.current_scope)

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

  # The role menu on a member's row. Your own role isn't offered, so an admin
  # can't demote themselves out of the page that would let them undo it.
  def handle_event("change_role", %{"user_id" => user_id, "role" => role}, %{assigns: %{current_scope: scope}} = socket) do
    authorized!(:"org_user:update", scope)

    with {:ok, org_user} <- Accounts.get_org_user(scope.org, user_id),
         false <- org_user.user_id == scope.user.id,
         {:ok, org_user} <- Accounts.change_org_user_role(org_user, role) do
      socket
      |> org_users()
      |> put_flash(:info, "#{org_user.user.name} is now #{role_label(org_user.role)}")
      |> noreply()
    else
      _ ->
        socket
        |> org_users()
        |> put_flash(:error, "Error updating role")
        |> noreply()
    end
  end

  def handle_event("delete_org_user", %{"user_id" => user_id}, %{assigns: %{current_scope: scope}} = socket) do
    {:ok, org_user_to_remove} = Accounts.get_org_user(socket.assigns.org, user_id)

    # Counted here rather than read from assigns: only the index page loads
    # `admin_count`, but the event can arrive from any page of this LiveView.
    can_remove!(org_user_to_remove, scope, length(Accounts.get_org_admins(scope.org)))

    case Accounts.remove_org_user(scope.org, org_user_to_remove.user) do
      :ok ->
        if org_user_to_remove.user.id == scope.user.id do
          _ = UserNotifier.deliver_all_tell_org_user_removed_themself(scope.org, scope.user)

          socket
          |> push_navigate(to: ~p"/orgs")
          |> put_flash(:info, "You have removed yourself from the #{scope.org.name} org")
          |> noreply()
        else
          _ = UserNotifier.deliver_all_tell_org_user_removed(scope.org, scope.user, org_user_to_remove.user)

          socket
          |> org_users()
          |> OrgCounts.refresh()
          |> put_flash(:info, "User removed")
          |> noreply()
        end

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not remove user")}
    end
  end

  @roles [:admin, :manage, :view]

  # Admins first, then by name, so the people who can change things are the
  # ones at the top.
  defp org_users(socket) do
    org_users =
      socket.assigns.org
      |> Accounts.get_org_users()
      |> Enum.sort_by(&{role_rank(&1.role), String.downcase(&1.user.name)})

    socket
    |> assign(:org_users, org_users)
    |> assign(:admin_count, Enum.count(org_users, fn ou -> ou.role == :admin end))
  end

  defp role_rank(role), do: Enum.find_index(@roles, &(&1 == role)) || length(@roles)

  defp role_label(role), do: role |> to_string() |> String.capitalize()

  # "3 admin · 2 manage · 4 view", leaving out roles nobody has.
  defp role_summary(org_users) do
    counts = Enum.frequencies_by(org_users, & &1.role)

    for role <- @roles, Map.has_key?(counts, role), do: "#{counts[role]} #{role}"
  end

  defp org_invites(socket) do
    assign(socket, :invites, Accounts.get_invites_for_org(socket.assigns.org))
  end

  # Only ever rendered for someone allowed to manage invites - the token is the
  # invite's credential, so it must not reach anybody else's DOM.
  # The link to copy, which doesn't have the key the emailed one has
  defp invite_url(invite), do: InviteLinks.shared_url(invite)

  # `invited_by_id` predates being required, so old invites can still be orphaned
  defp invited_by_name(%{invited_by: %{name: name}}), do: name
  defp invited_by_name(_invite), do: nil

  # An invite that has been accepted and one that has been declined both leave
  # the admin looking at a stale row, and they mean opposite things.
  defp invite_unavailable(:accepted), do: "it has already been accepted"
  defp invite_unavailable(:declined), do: "it has already been declined"
  defp invite_unavailable(:not_found), do: "it no longer exists"

  defp invite_action_title(true, description), do: description
  defp invite_action_title(false, _description), do: "Only org admins can manage invites"

  defp can_remove!(org_user, current_scope, admin_count) do
    can_remove?(org_user, current_scope, admin_count) || raise NervesHubWeb.UnauthorizedError
  end

  defp can_remove?(%{user: %{id: id}, role: role}, %{user: %{id: id}}, _) when role != :admin do
    true
  end

  defp can_remove?(org_user, current_scope, admin_count) do
    authorized?(:"org_user:delete", current_scope) && user_can_be_removed?(org_user, current_scope, admin_count)
  end

  defp user_can_be_removed?(%{user: %{id: id}}, %{user: %{id: id}}, 1), do: false
  defp user_can_be_removed?(_org_user, _current_scope, _), do: true

  defp remove_user_message(%{user: %{id: id}}, %{user: %{id: id}}) do
    "Are you sure you want to remove yourself from the org? This can not be undone."
  end

  defp remove_user_message(_org_user, _current_scope) do
    "Are you sure you want to remove this user? This can not be undone."
  end

  defp toggle_menu(user_id) do
    JS.toggle(
      to: "#member-#{user_id}-menu",
      in: {"ease-out duration-150", "opacity-0", "opacity-100"},
      out: {"ease-out duration-150", "opacity-100", "opacity-0"}
    )
  end

  defp hide_menu(js \\ %JS{}, user_id) do
    JS.hide(js,
      to: "#member-#{user_id}-menu",
      transition: {"ease-out duration-150", "opacity-100", "opacity-0"}
    )
  end

  ## Components

  attr(:org, :map, required: true)

  defp invite_button(assigns) do
    ~H"""
    <.button type="link" style="primary" navigate={~p"/org/#{@org}/settings/users/invite"} class="shrink-0">
      <span class="lucide-plus size-3.5" aria-hidden="true"></span> Invite people
    </.button>
    """
  end

  attr(:user, :map, required: true)

  # The tints only tell people apart at a glance, so they follow the user's id
  # rather than meaning anything.
  defp member_avatar(assigns) do
    assigns = assign(assigns, :tint, rem(assigns.user.id, 4))

    ~H"""
    <img :if={@user.profile_picture_url} src={@user.profile_picture_url} alt="" class="size-7.5 shrink-0 rounded-full object-cover" />
    <span
      :if={!@user.profile_picture_url}
      data-tint={@tint}
      class={[
        "flex size-7.5 shrink-0 items-center justify-center rounded-full text-[11px] font-semibold",
        "data-[tint=0]:bg-notice-soft data-[tint=0]:text-notice-content data-[tint=1]:bg-success-soft data-[tint=1]:text-success-content",
        "data-[tint=2]:bg-warning-soft data-[tint=2]:text-warning-content data-[tint=3]:bg-alert-soft data-[tint=3]:text-alert-content"
      ]}
      aria-hidden="true"
    >
      {initials(@user.name)}
    </span>
    """
  end

  defp initials(name) do
    name
    |> String.split()
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end
end
