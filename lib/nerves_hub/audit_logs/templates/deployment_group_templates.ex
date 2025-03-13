defmodule NervesHub.AuditLogs.DeploymentGroupTemplates do
  @moduledoc """
  Templates for and handling of audit logging for deployment operations.
  """
  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs
  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments.DeploymentGroup

  @spec audit_deployment_created(User.t(), DeploymentGroup.t()) :: :ok
  def audit_deployment_created(user, deployment_group) do
    description = "User #{user.name} created deployment group #{deployment_group.name}"
    AuditLogs.audit!(user, deployment_group, description)
  end

  @spec audit_deployment_updated(User.t(), DeploymentGroup.t()) :: :ok
  def audit_deployment_updated(user, deployment_group) do
    description = "User #{user.name} updated deployment group #{deployment_group.name}"
    AuditLogs.audit!(user, deployment_group, description)
  end

  @spec audit_deployment_deleted(User.t(), DeploymentGroup.t()) :: :ok
  def audit_deployment_deleted(user, deployment_group) do
    description = "User #{user.name} deleted deployment group #{deployment_group.name}"
    AuditLogs.audit!(user, deployment_group, description)
  end

  @spec audit_deployment_toggle_active(User.t(), DeploymentGroup.t(), String.t()) :: :ok
  def audit_deployment_toggle_active(user, deployment_group, status) do
    description = "User #{user.name} marked deployment group #{deployment_group.name} #{status}"
    AuditLogs.audit!(user, deployment_group, description)
  end

  @spec audit_deployment_mismatch(Device.t(), DeploymentGroup.t(), String.t()) :: :ok
  def audit_deployment_mismatch(device, deployment_group, reason) do
    description =
      "Device no longer matches deployment group #{deployment_group.name}'s requirements because of #{reason}"

    AuditLogs.audit!(device, deployment_group, description)
  end

  @spec audit_deployment_group_change(DeploymentGroup.t(), String.t()) :: :ok
  def audit_deployment_group_change(deployment_group, change_string) do
    description = "Deployment group #{deployment_group.name} #{change_string}"
    AuditLogs.audit!(deployment_group, deployment_group, description)
  end
end
