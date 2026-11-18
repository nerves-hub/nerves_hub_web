defmodule NervesHub.AuditLogs.DeploymentGroupTemplates do
  @moduledoc """
  Templates for and handling of audit logging for deployment operations.
  """
  alias NervesHub.AuditLogs
  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep

  @spec audit_deployment_created(AuditLogs.actor(), DeploymentGroup.t()) :: :ok
  def audit_deployment_created(actor, deployment_group) do
    description = "#{AuditLogs.actor_name(actor)} created deployment group #{deployment_group.name}"
    AuditLogs.audit!(actor, deployment_group, description)
  end

  @spec audit_new_deployment_release(AuditLogs.actor(), DeploymentGroup.t()) :: :ok
  def audit_new_deployment_release(actor, deployment_group) do
    description = "#{AuditLogs.actor_name(actor)} created a new release for deployment group #{deployment_group.name}"
    AuditLogs.audit!(actor, deployment_group, description)
  end

  @spec audit_release_required_changed(AuditLogs.actor(), DeploymentGroup.t(), DeploymentRelease.t()) :: :ok
  def audit_release_required_changed(actor, deployment_group, release) do
    change = if release.required, do: "marked", else: "unmarked"

    description =
      "#{AuditLogs.actor_name(actor)} #{change} release #{release.number} as required for deployment group #{deployment_group.name}"

    AuditLogs.audit!(actor, deployment_group, description)
  end

  @spec audit_release_connecting_code_changed(AuditLogs.actor(), DeploymentGroup.t(), DeploymentRelease.t()) :: :ok
  def audit_release_connecting_code_changed(actor, deployment_group, release) do
    description =
      "#{AuditLogs.actor_name(actor)} changed the connecting code for release #{release.number} of deployment group #{deployment_group.name}"

    AuditLogs.audit!(actor, deployment_group, description)
  end

  @spec audit_deployment_updated(AuditLogs.actor(), DeploymentGroup.t()) :: :ok
  def audit_deployment_updated(actor, deployment_group) do
    description = "#{AuditLogs.actor_name(actor)} updated deployment group #{deployment_group.name}"
    AuditLogs.audit!(actor, deployment_group, description)
  end

  @spec audit_deployment_deleted(AuditLogs.actor(), DeploymentGroup.t()) :: :ok
  def audit_deployment_deleted(actor, deployment_group) do
    description = "#{AuditLogs.actor_name(actor)} deleted deployment group #{deployment_group.name}"
    AuditLogs.audit!(actor, deployment_group, description)
  end

  @spec audit_deployment_toggle_active(AuditLogs.actor(), DeploymentGroup.t(), String.t()) :: :ok
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
  Somebody approved, skipped or retried a workflow step. `via` names where
  they did it when it was not the deployment group's page, such as a Slack
  actor.
  """
  @spec audit_workflow_step_action(
          AuditLogs.actor(),
          DeploymentGroup.t(),
          DeploymentWorkflowStep.t(),
          :approved | :skipped | :retried,
          String.t() | nil
        ) :: :ok
  def audit_workflow_step_action(actor, deployment_group, step, action, via \\ nil)
      when action in [:approved, :skipped, :retried] do
    description =
      "#{AuditLogs.actor_name(actor)} #{action} workflow step #{step.number} (#{DeploymentWorkflowStep.label(step)}) for deployment group #{deployment_group.name}#{via(via)}"

    AuditLogs.audit!(actor, deployment_group, description)
  end

  defp via(nil), do: ""
  defp via(source), do: " from #{source}"

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

  def audit_deployment_toggle_active(actor, deployment_group, status) do
    description = "#{AuditLogs.actor_name(actor)} marked deployment group #{deployment_group.name} #{status}"
    AuditLogs.audit!(actor, deployment_group, description)
  end

  @spec audit_deployment_mismatch(Device.t(), DeploymentGroup.t(), String.t()) :: :ok
  def audit_deployment_mismatch(device, deployment_group, reason) do
    description =
      "Device no longer matches deployment group #{deployment_group.name}'s requirements because of #{reason}"

    AuditLogs.audit!(device, deployment_group, description, kind: :deployment_group_mismatch)
  end

  @spec audit_deployment_group_change(DeploymentGroup.t(), String.t()) :: :ok
  def audit_deployment_group_change(deployment_group, change_string) do
    description = "Deployment group #{deployment_group.name} #{change_string}"
    AuditLogs.audit!(deployment_group, deployment_group, description)
  end
end
