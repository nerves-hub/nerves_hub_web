defmodule NervesHub.AuditLogs.DeploymentGroupTemplates do
  @moduledoc """
  Templates for and handling of audit logging for deployment operations.

  Each description is a `NervesHub.AuditLogs.Template`, so the web UI names
  the users, devices and deployment groups in it as they are when the entry
  is read, with a link to each.
  """
  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.Template
  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep

  @spec audit_deployment_created(AuditLogs.actor(), DeploymentGroup.t()) :: :ok
  def audit_deployment_created(actor, deployment_group) do
    AuditLogs.audit!(actor, deployment_group, Template.new("%{actor} created deployment group %{resource}"))
  end

  @spec audit_new_deployment_release(AuditLogs.actor(), DeploymentGroup.t()) :: :ok
  def audit_new_deployment_release(actor, deployment_group) do
    template = Template.new("%{actor} created a new release for deployment group %{resource}")
    AuditLogs.audit!(actor, deployment_group, template)
  end

  @spec audit_release_required_changed(AuditLogs.actor(), DeploymentGroup.t(), DeploymentRelease.t()) :: :ok
  def audit_release_required_changed(actor, deployment_group, release) do
    change = if release.required, do: "marked", else: "unmarked"

    template =
      Template.new("%{actor} #{change} release %{release} as required for deployment group %{resource}",
        release: release.number
      )

    AuditLogs.audit!(actor, deployment_group, template)
  end

  @spec audit_release_connecting_code_changed(AuditLogs.actor(), DeploymentGroup.t(), DeploymentRelease.t()) :: :ok
  def audit_release_connecting_code_changed(actor, deployment_group, release) do
    template =
      Template.new("%{actor} changed the connecting code for release %{release} of deployment group %{resource}",
        release: release.number
      )

    AuditLogs.audit!(actor, deployment_group, template)
  end

  @spec audit_deployment_updated(AuditLogs.actor(), DeploymentGroup.t()) :: :ok
  def audit_deployment_updated(actor, deployment_group) do
    AuditLogs.audit!(actor, deployment_group, Template.new("%{actor} updated deployment group %{resource}"))
  end

  @spec audit_deployment_deleted(AuditLogs.actor(), DeploymentGroup.t()) :: :ok
  def audit_deployment_deleted(actor, deployment_group) do
    AuditLogs.audit!(actor, deployment_group, Template.new("%{actor} deleted deployment group %{resource}"))
  end

  @spec audit_workflow_uploaded(AuditLogs.actor(), DeploymentGroup.t()) :: :ok
  def audit_workflow_uploaded(actor, deployment_group) do
    template = Template.new("%{actor} uploaded a new workflow definition to deployment group %{resource}")
    AuditLogs.audit!(actor, deployment_group, template)
  end

  @spec audit_workflow_removed(AuditLogs.actor(), DeploymentGroup.t()) :: :ok
  def audit_workflow_removed(actor, deployment_group) do
    template = Template.new("%{actor} removed the workflow definition from deployment group %{resource}")
    AuditLogs.audit!(actor, deployment_group, template)
  end

  @doc """
  A workflow step failed and stopped the rollout.

  The deployment group is the actor because nobody did this — enough of the
  step's devices failed to take the update that the step gave up.
  """
  @spec audit_workflow_step_failed(DeploymentGroup.t(), DeploymentWorkflowStep.t(), non_neg_integer()) :: :ok
  def audit_workflow_step_failed(deployment_group, step, failed_count) do
    template =
      Template.new(
        """
        Workflow step %{step} (%{label}) failed for deployment group %{resource}.
        %{failed} device(s) could not take the update, which is at or over the step's tolerance.
        No further devices will be updated for this release until the step is retried or skipped.
        """,
        step: step.number,
        label: DeploymentWorkflowStep.label(step),
        failed: failed_count
      )

    AuditLogs.audit!(deployment_group, deployment_group, template)
  end

  @doc """
  Somebody approved, skipped or retried a workflow step. `via` names where
  they did it when it was not the deployment group's page, such as a Slack
  user.
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
    text = "%{actor} #{action} workflow step %{step} (%{label}) for deployment group %{resource}"
    values = [step: step.number, label: DeploymentWorkflowStep.label(step)]

    template =
      if via,
        do: Template.new(text <> " from %{via}", [via: via] ++ values),
        else: Template.new(text, values)

    AuditLogs.audit!(actor, deployment_group, template)
  end

  @doc """
  A workflow reached a step that waits for someone to approve it.
  """
  @spec audit_workflow_awaiting_approval(DeploymentGroup.t(), DeploymentWorkflowStep.t()) :: :ok
  def audit_workflow_awaiting_approval(deployment_group, step) do
    template =
      Template.new(
        """
        Workflow step %{step} (%{label}) for deployment group %{resource} is waiting for approval.
        No further devices will be updated for this release until it is approved or skipped.
        """,
        step: step.number,
        label: DeploymentWorkflowStep.label(step)
      )

    AuditLogs.audit!(deployment_group, deployment_group, template)
  end

  @spec audit_deployment_toggle_active(AuditLogs.actor(), DeploymentGroup.t(), String.t()) :: :ok
  def audit_deployment_toggle_active(actor, deployment_group, status) do
    template = Template.new("%{actor} marked deployment group %{resource} %{status}", status: status)
    AuditLogs.audit!(actor, deployment_group, template)
  end

  @spec audit_deployment_mismatch(Device.t(), DeploymentGroup.t(), String.t()) :: :ok
  def audit_deployment_mismatch(device, deployment_group, reason) do
    template =
      Template.new(
        "Device %{actor} no longer matches deployment group %{resource}'s requirements because of %{reason}",
        reason: reason
      )

    AuditLogs.audit!(device, deployment_group, template, kind: :deployment_group_mismatch)
  end

  @doc """
  Something about the group changed on its own, as `change` says, such as
  "conditions changed".
  """
  @spec audit_deployment_group_change(DeploymentGroup.t(), String.t()) :: :ok
  def audit_deployment_group_change(deployment_group, change) do
    template = Template.new("Deployment group %{resource} %{change}", change: change)
    AuditLogs.audit!(deployment_group, deployment_group, template)
  end
end
