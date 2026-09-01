defmodule NervesHub.ManagedDeployments.Workflows do
  @moduledoc """
  Reading and advancing the workflow steps attached to a deployment release.

  Steps are generated when a release is created (see
  `NervesHub.ManagedDeployments.DeploymentRelease`) and are walked in `number`
  order by `NervesHub.ManagedDeployments.Orchestrator.WorkflowCoordinator`.

  Every transition broadcasts `step/updated` on `deployment_release:<id>` so an
  open deployment group page can move the step along without polling.
  """

  alias Ecto.Changeset
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.Repo
  alias Phoenix.Channel.Server, as: PhoenixChannelServer

  @doc """
  Mark a waiting step as in progress.
  """
  @spec start_step(DeploymentWorkflowStep.t()) :: DeploymentWorkflowStep.t()
  def start_step(step) do
    transition(step, status: :in_progress, started_at: now())
  end

  @doc """
  Mark an in-progress step as finished.
  """
  @spec complete_step(DeploymentWorkflowStep.t()) :: DeploymentWorkflowStep.t()
  def complete_step(step) do
    transition(step, status: :completed, finished_at: now())
  end

  defp transition(step, changes) do
    step = Repo.update!(Changeset.change(step, Map.new(changes)))

    :ok = broadcast(step, "step/updated", %{id: step.id, number: step.number, status: step.status})

    step
  end

  defp now(), do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

  @spec broadcast(DeploymentWorkflowStep.t(), String.t(), map()) :: :ok | {:error, term()}
  defp broadcast(%DeploymentWorkflowStep{deployment_release_id: release_id}, event, payload) do
    PhoenixChannelServer.broadcast(
      NervesHub.PubSub,
      "deployment_release:#{release_id}",
      event,
      payload
    )
  end
end
