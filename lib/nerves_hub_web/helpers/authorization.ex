defmodule NervesHubWeb.Helpers.Authorization do
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.Scope
  alias NervesHub.Accounts.User

  def authorized!(org_user, permission) do
    authorized?(org_user, permission) || raise NervesHubWeb.UnauthorizedError
  end

  def authorized?(:"organization:update", role), do: role_check(:admin, role)
  def authorized?(:"organization:delete", role), do: role_check(:admin, role)

  def authorized?(:"signing_key:create", role), do: role_check(:manage, role)
  def authorized?(:"signing_key:delete", role), do: role_check(:manage, role)

  def authorized?(:"org_user:update", role), do: role_check(:admin, role)
  def authorized?(:"org_user:delete", role), do: role_check(:admin, role)

  def authorized?(:"org_user:invite", role), do: role_check(:admin, role)
  def authorized?(:"org_user:invite:rescind", role), do: role_check(:admin, role)

  def authorized?(:"certificate_authority:create", role), do: role_check(:admin, role)
  def authorized?(:"certificate_authority:update", role), do: role_check(:admin, role)
  def authorized?(:"certificate_authority:delete", role), do: role_check(:admin, role)

  def authorized?(:"product:create", role), do: role_check(:manage, role)
  def authorized?(:"product:update", role), do: role_check(:manage, role)
  def authorized?(:"product:delete", role), do: role_check(:manage, role)

  def authorized?(:"product:notifications:dismiss", role), do: role_check(:manage, role)

  def authorized?(:"device:console", role), do: role_check(:manage, role)
  def authorized?(:"device:create", role), do: role_check(:manage, role)
  def authorized?(:"device:update", role), do: role_check(:manage, role)
  def authorized?(:"device:view", role), do: role_check(:view, role)

  def authorized?(:"device:set-deployment-group", role), do: role_check(:manage, role)

  def authorized?(:"device:push-update", role), do: role_check(:manage, role)
  def authorized?(:"device:toggle-updates", role), do: role_check(:manage, role)
  def authorized?(:"device:clear-penalty-box", role), do: role_check(:manage, role)
  def authorized?(:"device:identify", role), do: role_check(:manage, role)
  def authorized?(:"device:reboot", role), do: role_check(:manage, role)
  def authorized?(:"device:reconnect", role), do: role_check(:manage, role)
  def authorized?(:"device:delete", role), do: role_check(:manage, role)
  def authorized?(:"device:restore", role), do: role_check(:manage, role)
  def authorized?(:"device:destroy", role), do: role_check(:manage, role)

  def authorized?(:"device:extensions:local_shell", role), do: role_check(:manage, role)

  def authorized?(:"firmware:upload", role), do: role_check(:manage, role)
  def authorized?(:"firmware:delete", role), do: role_check(:manage, role)

  def authorized?(:"archive:upload", role), do: role_check(:manage, role)
  def authorized?(:"archive:delete", role), do: role_check(:manage, role)

  def authorized?(:"deployment_group:create", role), do: role_check(:manage, role)
  def authorized?(:"deployment_group:update", role), do: role_check(:manage, role)
  def authorized?(:"deployment_group:toggle", role), do: role_check(:manage, role)

  def authorized?(:"deployment_group:toggle_delta_updates", role), do: role_check(:manage, role)

  def authorized?(:"deployment_group:delete", role), do: role_check(:manage, role)

  def authorized?(:"support_script:create", role), do: role_check(:manage, role)
  def authorized?(:"support_script:update", role), do: role_check(:manage, role)
  def authorized?(:"support_script:delete", role), do: role_check(:manage, role)
  def authorized?(:"support_script:run", role), do: role_check(:view, role)

  defp role_check(required_role, %Scope{role: role}) do
    role_check(required_role, role)
  end

  defp role_check(required_role, %OrgUser{role: role}) do
    role_check(required_role, role)
  end

  defp role_check(required_role, user_role) do
    required_role
    |> User.role_or_higher()
    |> Enum.any?(&(&1 == user_role))
  end
end
