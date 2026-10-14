defmodule NervesHubWeb.Integrations.Slack.WorkflowSteps do
  @moduledoc """
  The buttons on NervesHub's Slack messages about a deployment workflow
  (`NervesHub.Integrations.Slack.Messages`): Approve on a workflow waiting for approval,
  and Retry and Skip on a step that failed.

  Each does what the same button on the deployment group's page does, as the
  NervesHub user the Slack user linked, checked as the device buttons are
  (`NervesHubWeb.Integrations.Slack.Actions.authorize_in/6`): the deployment group's
  organization is connected to the workspace the click came from, and the
  user's role there has `deployment_group:update`, at that moment. The
  button carries only the step's id.

  A message can be clicked long after it was posted, so the step is read
  back first, and acted on only if it is still part of the deployment
  group's current release and still in the state the button was for. One
  approved, retried or skipped since says by whom.

  A step is acted on from Slack once every 30 seconds, by a claim in
  Postgres (`NervesHub.Integrations.Slack.Claims`), so a double click, or two people
  clicking at once, approve or retry it once.

  What was done is audited with the Slack user who did it and posted in the
  message's thread. The orchestrator is then nudged to carry on, as the
  deployment group's page does.
  """

  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs.DeploymentGroupTemplates
  alias NervesHub.Integrations.Slack.Claims
  alias NervesHub.Integrations.Slack.Users
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.ManagedDeployments.Workflows
  alias NervesHub.Repo
  alias NervesHubWeb.Integrations.Slack.Actions

  @actions %{
    "workflow_step.approve" => :approve,
    "workflow_step.retry" => :retry,
    "workflow_step.skip" => :skip
  }

  @claim_seconds 30

  @typedoc "A click on one of the buttons, read from Slack's interaction payload."
  @type click() :: %{
          action: :approve | :retry | :skip,
          step_id: pos_integer(),
          team_id: String.t(),
          slack_user_id: String.t(),
          slack_username: String.t() | nil,
          response_url: String.t() | nil,
          channel_id: String.t() | nil,
          message_ts: String.t() | nil
        }

  @doc """
  The click, from Slack's interaction payload and the action in it, or `nil`
  for one that is not one of these buttons or names no step.
  """
  @spec click(map(), map()) :: click() | nil
  def click(payload, %{"action_id" => action_id, "value" => value}) when is_map_key(@actions, action_id) do
    with {:ok, step_id} <- Ecto.Type.cast(:id, value),
         %{} = clicked_by <- Actions.clicked_by(payload) do
      Map.merge(clicked_by, %{action: Map.fetch!(@actions, action_id), step_id: step_id})
    else
      _ -> nil
    end
  end

  def click(_payload, _action), do: nil

  @doc """
  Carries out a click, or tells the person who clicked why not. Returns
  what happened, for tests.
  """
  @spec perform(click()) :: {:ok, :approve | :retry | :skip} | {:error, atom()}
  def perform(%{action: action} = click) do
    with {:user, %User{} = user} <- {:user, Users.use_link(click.team_id, click.slack_user_id)},
         {:step, {%DeploymentWorkflowStep{} = step, %DeploymentGroup{} = deployment_group}} <-
           {:step, step(click.step_id)},
         :ok <-
           Actions.authorize_in(
             click.team_id,
             user,
             deployment_group.org,
             :"deployment_group:update",
             "#{verb(action)} deployment workflow steps",
             "that deployment group"
           ),
         :ok <- current(step, deployment_group),
         :ok <- still_possible(action, step),
         :ok <- claim(step, user),
         {:ok, step} <- act(action, deployment_group, step, user) do
      :ok =
        DeploymentGroupTemplates.audit_workflow_step_action(
          user,
          deployment_group,
          step,
          done_action(action),
          Actions.via(click)
        )

      # Approving or skipping only clears the way, and a retried step waits
      # for the next pass. The orchestrator is what moves the workflow on.
      :ok = ManagedDeployments.broadcast(deployment_group, "deployments/update")

      :ok = Actions.announce(click, done(action, user, step, deployment_group))
      {:ok, action}
    else
      {:user, nil} ->
        Actions.refuse(click, :not_linked, Actions.link_message(click.team_id))

      {:step, nil} ->
        Actions.refuse(click, :no_step, "That workflow step is no longer in #{Actions.platform()}.")

      {:error, reason, message} ->
        Actions.refuse(click, reason, message)
    end
  end

  # The step, and its deployment group with the organization the checks are
  # made against. A product or organization that was deleted takes its
  # deployment groups' workflows with it.
  defp step(id) do
    with %DeploymentWorkflowStep{} = step <- Repo.get(DeploymentWorkflowStep, id),
         %{deployment_group_id: deployment_group_id} <-
           Repo.get(DeploymentRelease, step.deployment_release_id),
         {:ok, %DeploymentGroup{org: %{}, product: %{}} = deployment_group} <-
           ManagedDeployments.get_deployment_group(deployment_group_id) do
      {step, deployment_group}
    else
      _ -> nil
    end
  end

  # A new release brings its own workflow, and the old one's steps are done
  # with, whatever state they were left in.
  defp current(step, deployment_group) do
    if step.deployment_release_id == deployment_group.current_deployment_release_id do
      :ok
    else
      {:error, :superseded,
       "#{step_label(step)} is part of an earlier release of #{group_label(deployment_group)}, so there is nothing more to do with it."}
    end
  end

  defp claim(step, user) do
    case Claims.claim("workflow_step:#{step.id}", @claim_seconds, user.name) do
      :ok ->
        :ok

      {:held, holder, _expires_at} ->
        by = if holder, do: " by #{Actions.escape(holder)}", else: ""
        {:error, :just_done, "#{step_label(step)} was acted on from Slack#{by} a moment ago, so it was left alone."}
    end
  end

  # Whether the step is still in the state the button was for. Asked before
  # the claim, so a click on an old message says what happened to the step
  # rather than only that it was claimed.
  defp still_possible(:approve, step) do
    cond do
      step.type != :approval_required ->
        {:error, :not_an_approval_step, "#{step_label(step)} does not wait for approval."}

      not is_nil(step.approved_at) ->
        {:error, :already_done, "#{step_label(step)} was already approved#{by(step.approved_by_id)}."}

      step.status != :in_progress ->
        {:error, :already_done, "#{step_label(step)} is no longer waiting for approval: it #{status(step)}."}

      true ->
        :ok
    end
  end

  defp still_possible(:retry, step) do
    if Workflows.retryable?(step),
      do: :ok,
      else: {:error, :not_retryable, "Only a failed step can be retried, and #{step_label(step)} #{status(step)}."}
  end

  defp still_possible(:skip, step) do
    cond do
      step.type == :catch_all ->
        {:error, :not_skippable, "#{step_label(step)} is the last step, so it cannot be skipped."}

      Workflows.skippable?(step) ->
        :ok

      true ->
        {:error, :not_skippable, "#{step_label(step)} can no longer be skipped: it #{status(step)}."}
    end
  end

  # The step as read before the claim. Anything that moved it since, such as
  # the dashboard, is caught by `Workflows` checking again.
  defp act(:approve, _deployment_group, step, user), do: {:ok, Workflows.approve_step(step, user)}

  defp act(:retry, deployment_group, step, user) do
    case Workflows.retry_step(deployment_group, step, user) do
      {:ok, step} -> {:ok, step}
      {:error, :not_retryable} -> {:error, :not_retryable, "#{step_label(step)} can no longer be retried."}
    end
  end

  defp act(:skip, _deployment_group, step, user) do
    case Workflows.skip_step(step, user) do
      {:ok, step} -> {:ok, step}
      {:error, :not_skippable} -> {:error, :not_skippable, "#{step_label(step)} can no longer be skipped."}
    end
  end

  defp status(%DeploymentWorkflowStep{status: :skipped, skipped_by_id: id}), do: "was skipped#{by(id)}"
  defp status(%DeploymentWorkflowStep{status: :waiting}), do: "has not started"
  defp status(%DeploymentWorkflowStep{status: :in_progress}), do: "is running"
  defp status(%DeploymentWorkflowStep{status: :completed}), do: "has completed"
  defp status(%DeploymentWorkflowStep{status: :error}), do: "failed"

  defp by(nil), do: ""

  defp by(user_id) do
    case Repo.get(User, user_id) do
      %User{name: name} -> " by #{Actions.escape(name)}"
      nil -> ""
    end
  end

  defp verb(:approve), do: "approve"
  defp verb(:retry), do: "retry"
  defp verb(:skip), do: "skip"

  defp done_action(:approve), do: :approved
  defp done_action(:retry), do: :retried
  defp done_action(:skip), do: :skipped

  defp done(action, user, step, deployment_group) do
    name = Actions.escape(user.name)
    step = step_label(step)
    group = group_label(deployment_group)

    case action do
      :approve -> ":white_check_mark: #{name} approved #{step} for #{group} from Slack. The rollout carries on."
      :retry -> ":repeat: #{name} retried #{step} for #{group} from Slack."
      :skip -> ":fast_forward: #{name} skipped #{step} for #{group} from Slack."
    end
  end

  defp step_label(step), do: "*#{Actions.escape(DeploymentWorkflowStep.label(step))}*"
  defp group_label(deployment_group), do: "*#{Actions.escape(deployment_group.name)}*"
end
