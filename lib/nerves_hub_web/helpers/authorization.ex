defmodule NervesHub.Errors.Unauthorized do
  defexception message: "unauthorized", plug_status: 401
end

defmodule NervesHub.Helpers.Authorization do
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.User

  def authorized!(org_user, permission) do
    authorized?(org_user, permission) || raise NervesHub.Errors.Unauthorized
  end

  def authorized?(:update_organization, %OrgUser{role: ur}), do: role_check(:admin, ur)
  def authorized?(:delete_organization, %OrgUser{role: ur}), do: role_check(:admin, ur)

  def authorized?(:save_signing_key, %OrgUser{role: ur}), do: role_check(:manage, ur)
  def authorized?(:delete_signing_key, %OrgUser{role: ur}), do: role_check(:manage, ur)

  def authorized?(:update_org_user, %OrgUser{role: ur}), do: role_check(:admin, ur)
  def authorized?(:delete_org_user, %OrgUser{role: ur}), do: role_check(:admin, ur)

  def authorized?(:invite_user, %OrgUser{role: ur}), do: role_check(:admin, ur)
  def authorized?(:rescind_invite, %OrgUser{role: ur}), do: role_check(:admin, ur)

  def authorized?(:add_certificate_authority, %OrgUser{role: ur}), do: role_check(:admin, ur)
  def authorized?(:update_certificate_authority, %OrgUser{role: ur}), do: role_check(:admin, ur)
  def authorized?(:delete_certificate_authority, %OrgUser{role: ur}), do: role_check(:admin, ur)

  def authorized?(:create_product, %OrgUser{role: user_role}), do: role_check(:manage, user_role)
  def authorized?(:update_product, %OrgUser{role: user_role}), do: role_check(:manage, user_role)
  def authorized?(:delete_product, %OrgUser{role: user_role}), do: role_check(:admin, user_role)

  def authorized?(:device_console, %OrgUser{role: user_role}), do: role_check(:manage, user_role)

  def authorized?(:"device:create", org_user), do: role_check(:manage, org_user.role)
  def authorized?(:"device:update", org_user), do: role_check(:manage, org_user.role)
  def authorized?(:"device:push-update", org_user), do: role_check(:manage, org_user.role)
  def authorized?(:"device:toggle-updates", org_user), do: role_check(:manage, org_user.role)
  def authorized?(:"device:clear-penalty-box", org_user), do: role_check(:manage, org_user.role)
  def authorized?(:"device:identify", org_user), do: role_check(:manage, org_user.role)
  def authorized?(:"device:reboot", org_user), do: role_check(:manage, org_user.role)
  def authorized?(:"device:reconnect", org_user), do: role_check(:manage, org_user.role)
  def authorized?(:"device:delete", org_user), do: role_check(:manage, org_user.role)
  def authorized?(:"device:restore", org_user), do: role_check(:manage, org_user.role)
  def authorized?(:"device:destroy", org_user), do: role_check(:manage, org_user.role)

  def authorized?(:upload_firmware, %OrgUser{role: user_role}), do: role_check(:manage, user_role)
  def authorized?(:delete_firmware, %OrgUser{role: user_role}), do: role_check(:manage, user_role)

  def authorized?(:"archive:upload", %OrgUser{role: user_role}),
    do: role_check(:manage, user_role)

  def authorized?(:"archive:delete", %OrgUser{role: user_role}),
    do: role_check(:manage, user_role)

  def authorized?(:create_support_script, %OrgUser{role: user_role}),
    do: role_check(:manage, user_role)

  def authorized?(:update_support_script, %OrgUser{role: user_role}),
    do: role_check(:manage, user_role)

  def authorized?(:delete_support_script, %OrgUser{role: user_role}),
    do: role_check(:manage, user_role)

  defp role_check(required_role, user_role) do
    required_role
    |> User.role_or_higher()
    |> Enum.any?(&(&1 == user_role))
  end
end
