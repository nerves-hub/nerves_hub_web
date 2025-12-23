defmodule NervesHub.AuditLogs.DeploymentGroupTemplates do
  @moduledoc """
  Templates for and handling of audit logging for deployment operations.
  """
  alias NervesHub.AuditLogs
  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments.DeploymentGroup

  @spec audit_deployment_created(AuditLogs.actor(), DeploymentGroup.t()) :: :ok
  def audit_deployment_created(actor, deployment_group) do
    actor_label = AuditLogs.actor_template(actor)
    description = "#{actor_label} created deployment group #{deployment_group.name}"
    AuditLogs.audit!(actor, deployment_group, description)
  end

  @spec audit_deployment_updated(AuditLogs.actor(), DeploymentGroup.t()) :: :ok
  def audit_deployment_updated(actor, deployment_group) do
    actor_label = AuditLogs.actor_template(actor)
    description = "#{actor_label} updated deployment group #{deployment_group.name}"
    AuditLogs.audit!(actor, deployment_group, description)
  end

  @spec audit_deployment_deleted(AuditLogs.actor(), DeploymentGroup.t()) :: :ok
  def audit_deployment_deleted(actor, deployment_group) do
    actor_label = AuditLogs.actor_template(actor)
    description = "#{actor_label} deleted deployment group #{deployment_group.name}"
    AuditLogs.audit!(actor, deployment_group, description)
  end

  @spec audit_deployment_toggle_active(AuditLogs.actor(), DeploymentGroup.t(), String.t()) ::
          :ok
  def audit_deployment_toggle_active(actor, deployment_group, status) do
    actor_label = AuditLogs.actor_template(actor)
    description = "#{actor_label} marked deployment group #{deployment_group.name} #{status}"
    AuditLogs.audit!(actor, deployment_group, description)
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
