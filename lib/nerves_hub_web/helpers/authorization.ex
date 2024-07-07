defmodule NervesHub.Errors.Unauthorized do
  defexception message: "unauthorized", plug_status: 401
end

defmodule NervesHub.Helpers.Authorization do
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.User

  def authorized!(org_user, permission) do
    authorized?(org_user, permission) || raise NervesHub.Errors.Unauthorized
  end

  def authorized?(:"organization:update", %OrgUser{role: ur}), do: role_check(:admin, ur)
  def authorized?(:"organization:delete", %OrgUser{role: ur}), do: role_check(:admin, ur)

  def authorized?(:"signing_key:create", %OrgUser{role: ur}), do: role_check(:manage, ur)
  def authorized?(:"signing_key:delete", %OrgUser{role: ur}), do: role_check(:manage, ur)

  def authorized?(:"org_user:update", %OrgUser{role: ur}), do: role_check(:admin, ur)
  def authorized?(:"org_user:delete", %OrgUser{role: ur}), do: role_check(:admin, ur)

  def authorized?(:"org_user:invite", %OrgUser{role: ur}), do: role_check(:admin, ur)
  def authorized?(:"org_user:invite:rescind", %OrgUser{role: ur}), do: role_check(:admin, ur)

  def authorized?(:"certificate_authority:create", %OrgUser{role: ur}), do: role_check(:admin, ur)
  def authorized?(:"certificate_authority:update", %OrgUser{role: ur}), do: role_check(:admin, ur)
  def authorized?(:"certificate_authority:delete", %OrgUser{role: ur}), do: role_check(:admin, ur)

  def authorized?(:"product:create", %OrgUser{role: ur}), do: role_check(:manage, ur)
  def authorized?(:"product:update", %OrgUser{role: ur}), do: role_check(:manage, ur)
  def authorized?(:"product:delete", %OrgUser{role: ur}), do: role_check(:manage, ur)

  def authorized?(:"device:console", %OrgUser{role: role}), do: role_check(:manage, role)

  def authorized?(:"device:create", %OrgUser{role: role}), do: role_check(:manage, role)
  def authorized?(:"device:update", %OrgUser{role: role}), do: role_check(:manage, role)
  def authorized?(:"device:push-update", %OrgUser{role: role}), do: role_check(:manage, role)
  def authorized?(:"device:toggle-updates", %OrgUser{role: role}), do: role_check(:manage, role)
  def authorized?(:"device:clear-penalty-box", %OrgUser{role: ur}), do: role_check(:manage, ur)
  def authorized?(:"device:identify", %OrgUser{role: role}), do: role_check(:manage, role)
  def authorized?(:"device:reboot", %OrgUser{role: role}), do: role_check(:manage, role)
  def authorized?(:"device:reconnect", %OrgUser{role: role}), do: role_check(:manage, role)
  def authorized?(:"device:delete", %OrgUser{role: role}), do: role_check(:manage, role)
  def authorized?(:"device:restore", %OrgUser{role: role}), do: role_check(:manage, role)
  def authorized?(:"device:destroy", %OrgUser{role: role}), do: role_check(:manage, role)

  def authorized?(:"firmware:upload", %OrgUser{role: role}), do: role_check(:manage, role)
  def authorized?(:"firmware:delete", %OrgUser{role: role}), do: role_check(:manage, role)

  def authorized?(:"archive:upload", %OrgUser{role: role}), do: role_check(:manage, role)
  def authorized?(:"archive:delete", %OrgUser{role: role}), do: role_check(:manage, role)

  def authorized?(:"deployment:create", %OrgUser{role: role}), do: role_check(:manage, role)
  def authorized?(:"deployment:update", %OrgUser{role: role}), do: role_check(:manage, role)
  def authorized?(:"deployment:toggle", %OrgUser{role: role}), do: role_check(:manage, role)
  def authorized?(:"deployment:delete", %OrgUser{role: role}), do: role_check(:manage, role)

  def authorized?(:"support_script:create", %OrgUser{role: role}), do: role_check(:manage, role)
  def authorized?(:"support_script:update", %OrgUser{role: role}), do: role_check(:manage, role)
  def authorized?(:"support_script:delete", %OrgUser{role: role}), do: role_check(:manage, role)

  defp role_check(required_role, user_role) do
    required_role
    |> User.role_or_higher()
    |> Enum.any?(&(&1 == user_role))
  end
end
