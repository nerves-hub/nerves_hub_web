defmodule NervesHubWeb.Live.Org.Roles do
  @moduledoc """
  The org's roles: the three built-in ones, which can be looked at but not
  changed, and the custom ones its admins create, edit and delete.
  """
  use NervesHubWeb, :live_view

  alias NervesHub.Accounts.OrgRole
  alias NervesHub.Accounts.OrgRoles
  alias NervesHub.Accounts.Permissions
  alias NervesHubWeb.Components.Utils

  embed_templates("role_templates/*")

  @built_in_roles Map.new(Permissions.built_in_roles(), &{Atom.to_string(&1), &1})

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
    |> page_title("Roles - #{socket.assigns.org.name}")
    |> assign_roles()
    |> sidebar_tab(:roles)
    |> render_with(&roles_template/1)
  end

  defp apply_action(socket, :show, %{"role" => role}) do
    role = fetch_role!(socket.assigns.org, role)

    socket
    |> page_title("#{Utils.role_name(role)} - Roles - #{socket.assigns.org.name}")
    |> assign(:role, role)
    |> assign(:granted, Permissions.for_role(role))
    |> sidebar_tab(:roles)
    |> render_with(&role_template/1)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> page_title("New Role - #{socket.assigns.org.name}")
    |> assign(:role, %OrgRole{})
    |> assign(:form, to_form(OrgRoles.change_org_role(%OrgRole{})))
    |> assign(:roles_to_copy, OrgRoles.list_org_roles(socket.assigns.org))
    |> sidebar_tab(:roles)
    |> render_with(&role_form_template/1)
  end

  defp apply_action(socket, :edit, %{"role" => role}) do
    role = fetch_custom_role!(socket.assigns.org, role)

    socket
    |> page_title("Edit #{role.name} - Roles - #{socket.assigns.org.name}")
    |> assign(:role, role)
    |> assign(:form, to_form(OrgRoles.change_org_role(role)))
    |> assign(:roles_to_copy, Enum.reject(OrgRoles.list_org_roles(socket.assigns.org), &(&1.id == role.id)))
    |> sidebar_tab(:roles)
    |> render_with(&role_form_template/1)
  end

  @impl Phoenix.LiveView
  # Picking a role to copy from replaces whatever is ticked with what that
  # role grants, as a starting point to adjust. Manage is offered, along with
  # the org's own roles; view grants a single permission a custom role can be
  # given, which is no starting point at all.
  def handle_event("validate", %{"_target" => ["org_role", "copy_from"], "org_role" => params}, socket) do
    params =
      case role_to_copy(socket.assigns.org, params["copy_from"]) do
        {:ok, role} -> Map.put(params, "permissions", permissions_to_copy(role))
        {:error, :not_found} -> params
      end

    validate(socket, params)
  end

  def handle_event("validate", %{"org_role" => params}, socket) do
    validate(socket, params)
  end

  def handle_event("save", %{"org_role" => params}, %{assigns: %{live_action: :new}} = socket) do
    %{current_scope: scope, org: org} = socket.assigns

    authorized!(:"org_role:create", scope)

    case OrgRoles.create_org_role(org, params) do
      {:ok, role} ->
        socket
        |> put_flash(:info, "Role #{role.name} created")
        |> push_navigate(to: ~p"/org/#{org}/settings/roles")
        |> noreply()

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("save", %{"org_role" => params}, %{assigns: %{live_action: :edit}} = socket) do
    %{current_scope: scope, org: org, role: role} = socket.assigns

    authorized!(:"org_role:update", scope)

    case OrgRoles.update_org_role(role, params) do
      {:ok, role} ->
        socket
        |> put_flash(:info, "Role #{role.name} updated")
        |> push_navigate(to: ~p"/org/#{org}/settings/roles")
        |> noreply()

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("delete", %{"role_id" => role_id}, socket) do
    %{current_scope: scope, org: org} = socket.assigns

    authorized!(:"org_role:delete", scope)

    with {:ok, role} <- OrgRoles.get_org_role(org, role_id),
         {:ok, role} <- OrgRoles.delete_org_role(role) do
      socket
      |> put_flash(:info, "Role #{role.name} deleted")
      |> push_patch(to: ~p"/org/#{org}/settings/roles")
      |> noreply()
    else
      {:error, :in_use} ->
        socket
        |> put_flash(
          :error,
          "This role is still in use. Move its members and outstanding invites to another role, then delete it."
        )
        |> noreply()

      {:error, _} ->
        socket
        |> assign_roles()
        |> put_flash(:error, "The role couldn't be deleted")
        |> noreply()
    end
  end

  defp validate(socket, params) do
    changeset =
      socket.assigns.role
      |> OrgRoles.change_org_role(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  defp assign_roles(socket) do
    socket
    |> assign(:custom_roles, OrgRoles.list_org_roles(socket.assigns.org))
    |> assign(:member_counts, OrgRoles.member_counts(socket.assigns.org))
  end

  defp fetch_role!(_org, role) when is_map_key(@built_in_roles, role), do: Map.fetch!(@built_in_roles, role)
  defp fetch_role!(org, id), do: fetch_custom_role!(org, id)

  # Built-in roles can't be edited, so their names aren't found here either.
  defp fetch_custom_role!(org, id) do
    case OrgRoles.get_org_role(org, id) do
      {:ok, role} -> role
      {:error, :not_found} -> raise Ecto.NoResultsError, queryable: OrgRole
    end
  end

  defp role_to_copy(_org, "manage"), do: {:ok, :manage}
  defp role_to_copy(org, "custom:" <> id), do: OrgRoles.get_org_role(org, id)
  defp role_to_copy(_org, _choice), do: {:error, :not_found}

  # What a role grants that a custom role can be given. A custom role's own
  # list can hold a permission that has since been removed or made admin-only;
  # going through what it grants leaves those behind.
  defp permissions_to_copy(role) do
    granted = Permissions.for_role(role)

    for %{custom_roles: :optional, name: name} <- Permissions.all(), name in granted, do: Atom.to_string(name)
  end

  defp role_path(org, role) when is_atom(role), do: ~p"/org/#{org}/settings/roles/#{role}"
  defp role_path(org, %OrgRole{id: id}), do: ~p"/org/#{org}/settings/roles/#{id}"

  defp built_in_description(:admin), do: "Everything, including managing the organization, its members and its roles."

  defp built_in_description(:manage),
    do: "Everything except managing the organization, its members, its roles and its certificate authorities."

  defp built_in_description(:view), do: "Can view everything and run support scripts, but can't change anything."

  defp member_count(member_counts, %OrgRole{id: id}), do: Map.get(member_counts, id, 0)
  defp member_count(member_counts, role), do: Map.get(member_counts, role, 0)

  defp checked?(form, permission) do
    Atom.to_string(permission) in List.wrap(form[:permissions].value)
  end

  # The permissions a custom role can be given, by group. Those every member
  # has, and those only the built-in admin role can have, aren't choices.
  defp offered_groups() do
    for {group, permissions} <- Permissions.grouped(),
        permissions = Enum.filter(permissions, &(&1.custom_roles == :optional)),
        permissions != [],
        do: {group, permissions}
  end
end
