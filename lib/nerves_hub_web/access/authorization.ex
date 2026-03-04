defmodule NervesHubWeb.Access.Authorization do
  alias NervesHub.Access
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgKey
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.User
  alias NervesHub.Archives.Archive
  alias NervesHub.Devices.CACertificate
  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Products.Product
  alias NervesHub.Scripts.Script

  def authorized!(permission, org_user, subject) do
    authorized?(permission, org_user, subject) || raise NervesHubWeb.UnauthorizedError
  end

  # Org-level permissions — subject: %Org{}
  def authorized?(:"organization:view", %OrgUser{} = ou, %Org{} = subject), do: role_check(:view, ou, subject)
  def authorized?(:"organization:update", %OrgUser{} = ou, %Org{} = subject), do: role_check(:admin, ou, subject)
  def authorized?(:"organization:delete", %OrgUser{} = ou, %Org{} = subject), do: role_check(:admin, ou, subject)

  def authorized?(:"signing_key:create", %OrgUser{} = ou, %Org{} = subject), do: role_check(:manage, ou, subject)
  def authorized?(:"signing_key:delete", %OrgUser{} = ou, %Org{} = subject), do: role_check(:manage, ou, subject)

  def authorized?(:"org_user:update", %OrgUser{} = ou, %Org{} = subject), do: role_check(:admin, ou, subject)
  def authorized?(:"org_user:delete", %OrgUser{} = ou, %Org{} = subject), do: role_check(:admin, ou, subject)
  def authorized?(:"org_user:invite", %OrgUser{} = ou, %Org{} = subject), do: role_check(:admin, ou, subject)
  def authorized?(:"org_user:invite:rescind", %OrgUser{} = ou, %Org{} = subject), do: role_check(:admin, ou, subject)

  def authorized?(:"certificate_authority:create", %OrgUser{} = ou, %Org{} = subject),
    do: role_check(:admin, ou, subject)

  def authorized?(:"certificate_authority:update", %OrgUser{} = ou, %Org{} = subject),
    do: role_check(:admin, ou, subject)

  def authorized?(:"certificate_authority:delete", %OrgUser{} = ou, %Org{} = subject),
    do: role_check(:admin, ou, subject)

  # Product-level permissions — subject: %Product{} (or %Org{} for create)
  def authorized?(:"product:view", %OrgUser{} = ou, %Product{} = subject), do: role_check(:view, ou, subject)
  def authorized?(:"product:create", %OrgUser{} = ou, %Org{} = subject), do: role_check(:manage, ou, subject)
  def authorized?(:"product:update", %OrgUser{} = ou, %Product{} = subject), do: role_check(:manage, ou, subject)
  def authorized?(:"product:delete", %OrgUser{} = ou, %Product{} = subject), do: role_check(:manage, ou, subject)

  # Device permissions — subject: %Device{} (or %Product{} for create/list)
  def authorized?(:"device:list", %OrgUser{} = ou, %Product{} = subject), do: role_check(:view, ou, subject)
  def authorized?(:"device:create", %OrgUser{} = ou, %Product{} = subject), do: role_check(:manage, ou, subject)
  def authorized?(:"device:view", %OrgUser{} = ou, %Device{} = subject), do: role_check(:view, ou, subject)
  def authorized?(:"device:update", %OrgUser{} = ou, %Device{} = subject), do: role_check(:manage, ou, subject)
  def authorized?(:"device:delete", %OrgUser{} = ou, %Device{} = subject), do: role_check(:manage, ou, subject)
  def authorized?(:"device:restore", %OrgUser{} = ou, %Device{} = subject), do: role_check(:manage, ou, subject)
  def authorized?(:"device:destroy", %OrgUser{} = ou, %Device{} = subject), do: role_check(:manage, ou, subject)
  def authorized?(:"device:console", %OrgUser{} = ou, %Device{} = subject), do: role_check(:manage, ou, subject)
  def authorized?(:"device:push-update", %OrgUser{} = ou, %Device{} = subject), do: role_check(:manage, ou, subject)
  def authorized?(:"device:toggle-updates", %OrgUser{} = ou, %Device{} = subject), do: role_check(:manage, ou, subject)

  def authorized?(:"device:clear-penalty-box", %OrgUser{} = ou, %Device{} = subject),
    do: role_check(:manage, ou, subject)

  def authorized?(:"device:identify", %OrgUser{} = ou, %Device{} = subject), do: role_check(:manage, ou, subject)
  def authorized?(:"device:reboot", %OrgUser{} = ou, %Device{} = subject), do: role_check(:manage, ou, subject)
  def authorized?(:"device:reconnect", %OrgUser{} = ou, %Device{} = subject), do: role_check(:manage, ou, subject)

  def authorized?(:"device:set-deployment-group", %OrgUser{} = ou, %Device{} = subject),
    do: role_check(:manage, ou, subject)

  def authorized?(:"device:extensions:local_shell", %OrgUser{} = ou, %Device{} = subject),
    do: role_check(:manage, ou, subject)

  # Device permissions — subject: list of device IDs (bulk operations)
  def authorized?(:"device:update", %OrgUser{role: role, org_id: org_id}, device_ids) when is_list(device_ids),
    do: role_sufficient?(:manage, role) and Access.org_owns_devices?(org_id, device_ids)

  def authorized?(:"device:toggle-updates", %OrgUser{role: role, org_id: org_id}, device_ids) when is_list(device_ids),
    do: role_sufficient?(:manage, role) and Access.org_owns_devices?(org_id, device_ids)

  def authorized?(:"device:clear-penalty-box", %OrgUser{role: role, org_id: org_id}, device_ids) when is_list(device_ids),
    do: role_sufficient?(:manage, role) and Access.org_owns_devices?(org_id, device_ids)

  def authorized?(:"device:set-deployment-group", %OrgUser{role: role, org_id: org_id}, device_ids)
      when is_list(device_ids),
      do: role_sufficient?(:manage, role) and Access.org_owns_devices?(org_id, device_ids)

  # Firmware permissions — subject: %Firmware{} (or %Product{} for upload/list)
  def authorized?(:"firmware:list", %OrgUser{} = ou, %Product{} = subject), do: role_check(:view, ou, subject)
  def authorized?(:"firmware:view", %OrgUser{} = ou, %Firmware{} = subject), do: role_check(:view, ou, subject)
  def authorized?(:"firmware:upload", %OrgUser{} = ou, %Product{} = subject), do: role_check(:manage, ou, subject)
  def authorized?(:"firmware:delete", %OrgUser{} = ou, %Firmware{} = subject), do: role_check(:manage, ou, subject)

  # Archive permissions — subject: %Archive{} (or %Product{} for upload/list)
  def authorized?(:"archive:list", %OrgUser{} = ou, %Product{} = subject), do: role_check(:view, ou, subject)
  def authorized?(:"archive:view", %OrgUser{} = ou, %Archive{} = subject), do: role_check(:view, ou, subject)
  def authorized?(:"archive:upload", %OrgUser{} = ou, %Product{} = subject), do: role_check(:manage, ou, subject)
  def authorized?(:"archive:delete", %OrgUser{} = ou, %Archive{} = subject), do: role_check(:manage, ou, subject)

  # Deployment group permissions — subject: %DeploymentGroup{} (or %Product{} for create/list)
  def authorized?(:"deployment_group:list", %OrgUser{} = ou, %Product{} = subject), do: role_check(:view, ou, subject)

  def authorized?(:"deployment_group:create", %OrgUser{} = ou, %Product{} = subject),
    do: role_check(:manage, ou, subject)

  def authorized?(:"deployment_group:view", %OrgUser{} = ou, %DeploymentGroup{} = subject),
    do: role_check(:view, ou, subject)

  def authorized?(:"deployment_group:update", %OrgUser{} = ou, %DeploymentGroup{} = subject),
    do: role_check(:manage, ou, subject)

  def authorized?(:"deployment_group:toggle", %OrgUser{} = ou, %DeploymentGroup{} = subject),
    do: role_check(:manage, ou, subject)

  def authorized?(:"deployment_group:toggle_delta_updates", %OrgUser{} = ou, %DeploymentGroup{} = subject),
    do: role_check(:manage, ou, subject)

  def authorized?(:"deployment_group:delete", %OrgUser{} = ou, %DeploymentGroup{} = subject),
    do: role_check(:manage, ou, subject)

  # Support script permissions — subject: %Script{} (or %Product{} for create/list)
  def authorized?(:"support_script:list", %OrgUser{} = ou, %Product{} = subject), do: role_check(:view, ou, subject)
  def authorized?(:"support_script:create", %OrgUser{} = ou, %Product{} = subject), do: role_check(:manage, ou, subject)
  def authorized?(:"support_script:view", %OrgUser{} = ou, %Script{} = subject), do: role_check(:view, ou, subject)
  def authorized?(:"support_script:update", %OrgUser{} = ou, %Script{} = subject), do: role_check(:manage, ou, subject)
  def authorized?(:"support_script:delete", %OrgUser{} = ou, %Script{} = subject), do: role_check(:manage, ou, subject)
  def authorized?(:"support_script:run", %OrgUser{} = ou, %Script{} = subject), do: role_check(:view, ou, subject)

  defp role_check(required_role, %OrgUser{role: user_role} = ou, subject) do
    role_sufficient?(required_role, user_role) and subject_match?(ou, subject)
  end

  defp role_sufficient?(required_role, user_role) do
    required_role
    |> User.role_or_higher()
    |> Enum.any?(&(&1 == user_role))
  end

  # Org: OrgUser.org_id must match the Org's id
  defp subject_match?(%OrgUser{org_id: org_id}, %Org{id: org_id}), do: true

  # Subjects with org_id: direct comparison
  defp subject_match?(%OrgUser{org_id: org_id}, %subject_mod{org_id: org_id})
       when subject_mod in [Product, Device, Firmware, DeploymentGroup, OrgKey, CACertificate], do: true

  # Archive and Script: no org_id, must check through Product via DB
  defp subject_match?(%OrgUser{org_id: org_id}, %Archive{} = archive), do: Access.org_owns_archive?(org_id, archive)
  defp subject_match?(%OrgUser{org_id: org_id}, %Script{} = script), do: Access.org_owns_script?(org_id, script)

  # No match
  defp subject_match?(_ou, _subject), do: false
end
