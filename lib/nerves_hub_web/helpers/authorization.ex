defmodule NervesHubWeb.Helpers.Authorization do
  @moduledoc """
  Checks whether a member may do something in their organization.

  Permissions and the roles that grant them are defined in
  `NervesHub.Accounts.Permissions`.
  """

  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.Permissions
  alias NervesHub.Accounts.Scope

  def authorized!(permission, subject) do
    authorized?(permission, subject) || raise NervesHubWeb.UnauthorizedError
  end

  @doc """
  Whether `subject` holds `permission`.

  `subject` is a `Scope` with an org (its permissions were worked out when the
  role was put on it), an `OrgUser` (with its custom role preloaded, if it has
  one), or a built-in role. Raises `ArgumentError` for a permission that
  doesn't exist.
  """
  def authorized?(permission, %Scope{permissions: permissions}) do
    Permissions.granted?(permissions, permission)
  end

  def authorized?(permission, %OrgUser{} = org_user) do
    Permissions.granted?(Permissions.for_role(OrgUser.assigned_role(org_user)), permission)
  end

  def authorized?(permission, role) when is_atom(role) do
    Permissions.granted?(Permissions.for_role(role), permission)
  end
end
