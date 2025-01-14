defmodule NervesHub.AuditLogs.DeploymentTemplates do
  @moduledoc """
  Templates for and handling of audit logging for deployment operations.
  """
  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.AuditLog
  alias NervesHub.Deployments.Deployment

  @spec audit_deployment_created(User.t(), Deployment.t()) :: AuditLog.t()
  def audit_deployment_created(user, deployment) do
    description = "#{user.name} created deployment #{deployment.name}"
    AuditLogs.audit!(user, deployment, description)
  end

  @spec audit_deployment_updated(User.t(), Deployment.t()) :: AuditLog.t()
  def audit_deployment_updated(user, deployment) do
    description = "#{user.name} updated deployment #{deployment.name}"
    AuditLogs.audit!(user, deployment, description)
  end

  @spec audit_deployment_deleted(User.t(), Deployment.t()) :: AuditLog.t()
  def audit_deployment_deleted(user, deployment) do
    description = "#{user.name} deleted deployment #{deployment.name}"
    AuditLogs.audit!(user, deployment, description)
  end

  @spec audit_deployment_toggle_active(User.t(), Deployment.t(), String.t()) :: AuditLog.t()
  def audit_deployment_toggle_active(user, deployment, status) do
    description = "#{user.name} marked deployment #{deployment.name} #{status}"
    AuditLogs.audit!(user, deployment, description)
  end

  @spec audit_deployment_mismatch(Device.t(), Deployment.t(), String.t()) :: AuditLog.t()
  def audit_deployment_mismatch(device, deployment, reason) do
    description =
      "device no longer matches deployment #{deployment.name}'s requirements because of #{reason}"

    AuditLogs.audit!(device, deployment, description)
  end

  @spec audit_deployment_change(Deployment.t(), String.t()) :: AuditLog.t()
  def audit_deployment_change(deployment, change_string) do
    description = "deployment #{deployment.name} #{change_string}"
    AuditLogs.audit!(deployment, deployment, description)
  end
end
