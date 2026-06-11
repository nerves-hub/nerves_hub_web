defmodule NervesHubWeb.Access.Authorization do
  alias NervesHub.Access
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.Scope
  alias NervesHub.Accounts.User
  alias NervesHub.Archives.Archive
  alias NervesHub.Devices.CACertificate
  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Products.Product
  alias NervesHub.Scripts.Script

  def authorized!(permission, scope, subject) do
    authorized?(permission, scope, subject) || raise NervesHubWeb.UnauthorizedError
  end

  # Org-level permissions — subject: %Org{}
  def authorized?(:"organization:view", %Scope{} = s, %Org{} = subject), do: role_check(:view, s, subject)
  def authorized?(:"organization:update", %Scope{} = s, %Org{} = subject), do: role_check(:admin, s, subject)
  def authorized?(:"organization:delete", %Scope{} = s, %Org{} = subject), do: role_check(:admin, s, subject)

  def authorized?(:"signing_key:create", %Scope{} = s, %Org{} = subject), do: role_check(:manage, s, subject)
  def authorized?(:"signing_key:delete", %Scope{} = s, %Org{} = subject), do: role_check(:manage, s, subject)

  def authorized?(:"org_user:update", %Scope{} = s, %Org{} = subject), do: role_check(:admin, s, subject)
  def authorized?(:"org_user:delete", %Scope{} = s, %Org{} = subject), do: role_check(:admin, s, subject)
  def authorized?(:"org_user:invite", %Scope{} = s, %Org{} = subject), do: role_check(:admin, s, subject)
  def authorized?(:"org_user:invite:rescind", %Scope{} = s, %Org{} = subject), do: role_check(:admin, s, subject)

  def authorized?(:"certificate_authority:create", %Scope{} = s, %Org{} = subject), do: role_check(:admin, s, subject)

  def authorized?(:"certificate_authority:update", %Scope{} = s, %Org{} = subject), do: role_check(:admin, s, subject)

  def authorized?(:"certificate_authority:delete", %Scope{} = s, %Org{} = subject), do: role_check(:admin, s, subject)

  # Product-level permissions — subject: %Product{} (or %Org{} for create)
  def authorized?(:"product:view", %Scope{} = s, %Product{} = subject), do: role_check(:view, s, subject)
  def authorized?(:"product:create", %Scope{} = s, %Org{} = subject), do: role_check(:manage, s, subject)
  def authorized?(:"product:update", %Scope{} = s, %Product{} = subject), do: role_check(:manage, s, subject)
  def authorized?(:"product:delete", %Scope{} = s, %Product{} = subject), do: role_check(:manage, s, subject)

  # Device permissions — subject: %Product{} (product-level) or %Device{} (entity-specific)
  def authorized?(:"device:list", %Scope{} = s, %Product{} = subject), do: role_check(:view, s, subject)
  def authorized?(:"device:create", %Scope{} = s, %Product{} = subject), do: role_check(:manage, s, subject)
  def authorized?(:"device:update", %Scope{} = s, %Product{} = subject), do: role_check(:manage, s, subject)
  def authorized?(:"device:delete", %Scope{} = s, %Product{} = subject), do: role_check(:manage, s, subject)
  def authorized?(:"device:toggle-updates", %Scope{} = s, %Product{} = subject), do: role_check(:manage, s, subject)
  def authorized?(:"device:clear-penalty-box", %Scope{} = s, %Product{} = subject), do: role_check(:manage, s, subject)

  def authorized?(:"device:set-deployment-group", %Scope{} = s, %Product{} = subject),
    do: role_check(:manage, s, subject)

  def authorized?(:"device:view", %Scope{} = s, %Device{} = subject), do: role_check(:view, s, subject)
  def authorized?(:"device:update", %Scope{} = s, %Device{} = subject), do: role_check(:manage, s, subject)
  def authorized?(:"device:delete", %Scope{} = s, %Device{} = subject), do: role_check(:manage, s, subject)
  def authorized?(:"device:restore", %Scope{} = s, %Device{} = subject), do: role_check(:manage, s, subject)
  def authorized?(:"device:destroy", %Scope{} = s, %Device{} = subject), do: role_check(:manage, s, subject)
  def authorized?(:"device:console", %Scope{} = s, %Device{} = subject), do: role_check(:manage, s, subject)
  def authorized?(:"device:push-update", %Scope{} = s, %Device{} = subject), do: role_check(:manage, s, subject)

  def authorized?(:"device:toggle-updates", %Scope{} = s, %Device{} = subject), do: role_check(:manage, s, subject)

  def authorized?(:"device:clear-penalty-box", %Scope{} = s, %Device{} = subject), do: role_check(:manage, s, subject)

  def authorized?(:"device:identify", %Scope{} = s, %Device{} = subject), do: role_check(:manage, s, subject)
  def authorized?(:"device:reboot", %Scope{} = s, %Device{} = subject), do: role_check(:manage, s, subject)
  def authorized?(:"device:reconnect", %Scope{} = s, %Device{} = subject), do: role_check(:manage, s, subject)

  def authorized?(:"device:set-deployment-group", %Scope{} = s, %Device{} = subject),
    do: role_check(:manage, s, subject)

  def authorized?(:"device:extensions:local_shell", %Scope{} = s, %Device{} = subject),
    do: role_check(:manage, s, subject)

  # Device permissions — subject: list of device IDs (bulk operations)
  def authorized?(:"device:update", %Scope{role: role, org: %Org{id: org_id}}, device_ids) when is_list(device_ids),
    do: role_sufficient?(:manage, role) and Access.org_owns_devices?(org_id, device_ids)

  def authorized?(:"device:toggle-updates", %Scope{role: role, org: %Org{id: org_id}}, device_ids)
      when is_list(device_ids), do: role_sufficient?(:manage, role) and Access.org_owns_devices?(org_id, device_ids)

  def authorized?(:"device:clear-penalty-box", %Scope{role: role, org: %Org{id: org_id}}, device_ids)
      when is_list(device_ids), do: role_sufficient?(:manage, role) and Access.org_owns_devices?(org_id, device_ids)

  def authorized?(:"device:set-deployment-group", %Scope{role: role, org: %Org{id: org_id}}, device_ids)
      when is_list(device_ids), do: role_sufficient?(:manage, role) and Access.org_owns_devices?(org_id, device_ids)

  # Firmware permissions — subject: %Firmware{} (or %Product{} for upload/list)
  def authorized?(:"firmware:list", %Scope{} = s, %Product{} = subject), do: role_check(:view, s, subject)
  def authorized?(:"firmware:view", %Scope{} = s, %Firmware{} = subject), do: role_check(:view, s, subject)
  def authorized?(:"firmware:upload", %Scope{} = s, %Product{} = subject), do: role_check(:manage, s, subject)
  def authorized?(:"firmware:delete", %Scope{} = s, %Firmware{} = subject), do: role_check(:manage, s, subject)

  # Archive permissions — subject: %Archive{} (or %Product{} for upload/list)
  def authorized?(:"archive:list", %Scope{} = s, %Product{} = subject), do: role_check(:view, s, subject)
  def authorized?(:"archive:view", %Scope{} = s, %Archive{} = subject), do: role_check(:view, s, subject)
  def authorized?(:"archive:upload", %Scope{} = s, %Product{} = subject), do: role_check(:manage, s, subject)
  def authorized?(:"archive:delete", %Scope{} = s, %Archive{} = subject), do: role_check(:manage, s, subject)

  # Deployment group permissions — subject: %DeploymentGroup{} (or %Product{} for create/list)
  def authorized?(:"deployment_group:list", %Scope{} = s, %Product{} = subject), do: role_check(:view, s, subject)

  def authorized?(:"deployment_group:create", %Scope{} = s, %Product{} = subject), do: role_check(:manage, s, subject)

  def authorized?(:"deployment_group:view", %Scope{} = s, %DeploymentGroup{} = subject),
    do: role_check(:view, s, subject)

  def authorized?(:"deployment_group:update", %Scope{} = s, %DeploymentGroup{} = subject),
    do: role_check(:manage, s, subject)

  def authorized?(:"deployment_group:toggle", %Scope{} = s, %DeploymentGroup{} = subject),
    do: role_check(:manage, s, subject)

  def authorized?(:"deployment_group:toggle_delta_updates", %Scope{} = s, %DeploymentGroup{} = subject),
    do: role_check(:manage, s, subject)

  def authorized?(:"deployment_group:delete", %Scope{} = s, %DeploymentGroup{} = subject),
    do: role_check(:manage, s, subject)

  # Support script permissions — subject: %Script{} (or %Product{} for create/list)
  def authorized?(:"support_script:list", %Scope{} = s, %Product{} = subject), do: role_check(:view, s, subject)

  def authorized?(:"support_script:create", %Scope{} = s, %Product{} = subject), do: role_check(:manage, s, subject)

  def authorized?(:"support_script:view", %Scope{} = s, %Script{} = subject), do: role_check(:view, s, subject)

  def authorized?(:"support_script:update", %Scope{} = s, %Script{} = subject), do: role_check(:manage, s, subject)

  def authorized?(:"support_script:delete", %Scope{} = s, %Script{} = subject), do: role_check(:manage, s, subject)

  def authorized?(:"support_script:run", %Scope{} = s, %Script{} = subject), do: role_check(:view, s, subject)

  defp role_check(required_role, %Scope{role: user_role, org: scope_org}, subject) do
    role_sufficient?(required_role, user_role) and subject_match?(scope_org, subject)
  end

  defp role_sufficient?(required_role, user_role) do
    required_role
    |> User.role_or_higher()
    |> Enum.any?(&(&1 == user_role))
  end

  # Org: scope org id must match the Org's id
  defp subject_match?(%Org{id: org_id}, %Org{id: org_id}), do: true

  # Subjects with org_id: direct comparison
  defp subject_match?(%Org{id: org_id}, %subject_mod{org_id: org_id})
       when subject_mod in [Product, Device, Firmware, DeploymentGroup, CACertificate], do: true

  # Archive and Script: no org_id, must check through Product via DB
  defp subject_match?(%Org{id: org_id}, %Archive{} = archive), do: Access.org_owns_archive?(org_id, archive)
  defp subject_match?(%Org{id: org_id}, %Script{} = script), do: Access.org_owns_script?(org_id, script)

  # No match
  defp subject_match?(_org, _subject), do: false
end
