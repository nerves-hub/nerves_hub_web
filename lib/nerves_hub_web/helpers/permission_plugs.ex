defmodule NervesHubWeb.Helpers.PermissionPlugs do
  @moduledoc """
  Controller plugs that check what the signed-in user may do in the org a
  request is for.

  Every member can read; anything else needs a permission from
  `NervesHub.Accounts.Permissions`, the same ones the dashboard checks.

  The org and the user's role in it come from the scope. `assign_org_to_scope`
  puts them there for routes with an `:org_name`, and
  `NervesHubWeb.API.Plugs.Device` does for the top-level
  `/api/devices/:identifier` routes, which have none.
  """

  alias NervesHub.Accounts.Scope
  alias NervesHubWeb.Helpers.Authorization

  @doc """
  Refuses the request unless the user is a member of the scope's org.
  """
  def require_membership(%{assigns: %{current_scope: %Scope{org: org, role: role}}} = conn, _opts)
      when not is_nil(org) and not is_nil(role) do
    conn
  end

  def require_membership(_conn, _opts), do: raise(NervesHubWeb.UnauthorizedError)

  @doc """
  Refuses the request unless the user holds `permission` in the scope's org.
  """
  def require_permission(%{assigns: %{current_scope: %Scope{org: org} = scope}} = conn, permission)
      when not is_nil(org) do
    Authorization.authorized!(permission, scope)

    conn
  end

  def require_permission(_conn, _permission), do: raise(NervesHubWeb.UnauthorizedError)
end
