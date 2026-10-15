defmodule NervesHub.ManagedDeployments.WorkflowEvents do
  @moduledoc """
  What a deployment workflow tells an organization's webhooks and Slack
  channels as its steps move (`NervesHub.Integrations.dispatch/3`):

    * `deployment_group.workflow_step.started`: a step began updating its
      devices, or began again after somebody retried it
    * `deployment_group.workflow_step.awaiting_approval`: the workflow
      reached an approval step, which is raised in place of `started` for
      one
    * `deployment_group.workflow_step.completed`: every device the step
      covers is on the release's firmware or, for an approval step,
      somebody approved it
    * `deployment_group.workflow_step.failed`: more of the step's devices
      failed to update than it tolerates, and the workflow stopped there
    * `deployment_group.workflow_step.skipped`: somebody skipped the step

  `NervesHub.ManagedDeployments.Workflows` raises each one as it writes the
  change, so a step moved by the orchestrator, from the dashboard or from
  Slack is announced the same way. The data is
  `NervesHub.Webhooks.Payloads.workflow_step/3`.
  """

  import Ecto.Query

  alias NervesHub.Accounts.User
  alias NervesHub.Integrations
  alias NervesHub.Integrations.Slack.WorkflowMessages
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.Repo
  alias NervesHub.Webhooks.Payloads

  @events ~w(started awaiting_approval completed failed skipped)

  @doc """
  Raises `event` (one of #{Enum.map_join(@events, ", ", &"`#{&1}`")}) for the
  step.

  `opts`:

    * `:user`: who did it, when somebody did: the `User` who skipped or
      retried the step, or the id of the one who approved it
    * `:failed_devices`: for `failed`, how many of its devices could not
      take the update
  """
  @spec announce(DeploymentWorkflowStep.t(), String.t(), keyword()) :: :ok
  def announce(%DeploymentWorkflowStep{} = step, event, opts \\ []) when event in @events do
    case release(step) do
      nil ->
        :ok

      release ->
        Integrations.dispatch(release.product_id, type(event), fn ->
          Payloads.workflow_step(step, release, user: user(opts[:user]), failed_devices: opts[:failed_devices])
        end)
    end
  end

  defp type(event), do: "deployment_group.workflow_step." <> event

  @doc """
  Says that `user` approved, retried or skipped a step (`change`), on the
  Slack messages that had buttons for it
  (`NervesHub.Integrations.Slack.WorkflowMessages`).
  """
  @spec resolved(DeploymentWorkflowStep.t(), String.t(), User.t()) :: :ok
  def resolved(%DeploymentWorkflowStep{id: id}, change, %User{name: name})
      when change in ~w(approved retried skipped) do
    WorkflowMessages.resolve([id], %{"change" => change, "by" => name})
  end

  @doc """
  Says that `release` replaced the deployment group's previous release, on
  the Slack messages that had buttons for the previous release's steps: they
  can no longer be approved, retried or skipped.
  """
  @spec release_replaced(pos_integer() | nil, DeploymentRelease.t()) :: :ok
  def release_replaced(nil, _release), do: :ok
  def release_replaced(previous_id, %DeploymentRelease{id: previous_id}), do: :ok

  def release_replaced(previous_id, %DeploymentRelease{number: number}) do
    step_ids =
      DeploymentWorkflowStep
      |> where([s], s.deployment_release_id == ^previous_id)
      |> select([s], s.id)
      |> Repo.all()

    WorkflowMessages.resolve(step_ids, %{"change" => "replaced", "release" => number})
  end

  # What every event says about where the step is, read in one query. A
  # release whose deployment group has gone has nobody left to tell.
  defp release(step) do
    DeploymentRelease
    |> where([r], r.id == ^step.deployment_release_id)
    |> join(:inner, [r], dg in assoc(r, :deployment_group))
    |> join(:left, [r], f in assoc(r, :firmware))
    |> select([r, dg, f], %{
      product_id: dg.product_id,
      deployment_group: %{name: dg.name},
      number: r.number,
      firmware: %{uuid: f.uuid, version: f.version}
    })
    |> Repo.one()
  end

  defp user(nil), do: nil
  defp user(%User{} = user), do: user
  defp user(id) when is_integer(id), do: Repo.get(User, id)
end
