defmodule NervesHub.AuditLogs.DeploymentGroupTemplates do
  @moduledoc """
  Templates for and handling of audit logging for deployment operations.
  """
  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs
  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep

  @spec audit_deployment_created(User.t(), DeploymentGroup.t()) :: :ok
  def audit_deployment_created(user, deployment_group) do
    description = "User #{user.name} created deployment group #{deployment_group.name}"
    AuditLogs.audit!(user, deployment_group, description)
  end

  @spec audit_new_deployment_release(User.t(), DeploymentGroup.t()) :: :ok
  def audit_new_deployment_release(user, deployment_group) do
    description = "User #{user.name} created a new release for deployment group #{deployment_group.name}"
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
  @doc """
  A workflow step failed and stopped the rollout.

  The deployment group is the actor because nobody did this — enough of the
  step's devices failed to take the update that the step gave up.
  """
  def audit_workflow_step_failed(deployment_group, step, failed_count) do
    description = """
    Workflow step #{step.number} (#{DeploymentWorkflowStep.label(step)}) failed for deployment group #{deployment_group.name}.
    #{failed_count} device(s) could not take the update, which is at or over the step's tolerance.
    No further devices will be updated for this release until the step is retried or skipped.
    """

    AuditLogs.audit!(deployment_group, deployment_group, description)
  end

  @doc """
  A workflow reached a step that waits for someone to approve it.
  """
  def audit_workflow_awaiting_approval(deployment_group, step) do
    description = """
    Workflow step #{step.number} (#{DeploymentWorkflowStep.label(step)}) for deployment group #{deployment_group.name} is waiting for approval.
    No further devices will be updated for this release until it is approved or skipped.
    """

    AuditLogs.audit!(deployment_group, deployment_group, description)
  end

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
