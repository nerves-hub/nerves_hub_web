defmodule NervesHub.ManagedDeployments.Workflows do
  @moduledoc """
  Reading and advancing the workflow steps attached to a deployment release.

  Steps are generated when a release is created (see
  `NervesHub.ManagedDeployments.DeploymentRelease`) and are walked in `number`
  order by `NervesHub.ManagedDeployments.Orchestrator.WorkflowCoordinator`.

  ## Which devices a step covers

  A step's membership is decided once and then recorded, rather than recomputed
  on every pass. `match_limit: 20` means "twenty canaries", and re-running the
  match each time would pick a different twenty as devices connect and
  disconnect, so a step would never finish. `claim_devices/2` writes the devices
  it picked into `deployment_workflow_steps_devices` and only ever tops the step
  up towards its limit.

  A device belongs to at most one step of a release. Claiming skips anything an
  earlier step already took, which is what stops the trailing `catch_all` from
  swallowing the canaries.

  Matching does not consider whether a device is connected — an offline canary is
  still a canary, and excluding it would let the workflow declare a stage good
  without ever having tried it. Connectivity is a scheduling question, answered
  later by `NervesHub.Devices.Updates.available_for_workflow_step/3`.

  Every transition broadcasts `step/updated` on `deployment_release:<id>` so an
  open deployment group page can move the step along without polling.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias NervesHub.Accounts.User
  alias NervesHub.Devices.Device
  alias NervesHub.FirmwareUpdates
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.Repo
  alias Phoenix.Channel.Server, as: PhoenixChannelServer

  require Logger

  @join_table "deployment_workflow_steps_devices"

  @doc """
  The steps of a release, in order.

  The orchestrator keeps a deployment group in its state for the life of the
  release, so the steps preloaded alongside it go stale as soon as one is
  started or completed. Read them back rather than trusting that copy.
  """
  @spec release_steps(integer()) :: [DeploymentWorkflowStep.t()]
  def release_steps(deployment_release_id) do
    DeploymentWorkflowStep
    |> where([s], s.deployment_release_id == ^deployment_release_id)
    |> order_by([s], asc: s.number)
    |> Repo.all()
  end

  @doc """
  The step currently holding the workflow open for someone to approve, if any.

  Only a started step counts. An approval step further down the list has not been
  reached yet, and asking about it early would be asking about a decision that may
  never need making.
  """
  @spec awaiting_approval(integer()) :: DeploymentWorkflowStep.t() | nil
  def awaiting_approval(nil), do: nil

  def awaiting_approval(deployment_release_id) do
    DeploymentWorkflowStep
    |> where([s], s.deployment_release_id == ^deployment_release_id)
    |> where([s], s.type == :approval_required and s.status == :in_progress and is_nil(s.approved_at))
    |> Repo.one()
  end

  @doc """
  Assign matching devices to a step, up to its match limit.

  Returns the number of devices newly claimed. Safe to call repeatedly: a step
  short of its limit tops up as more devices appear, and one already at its limit
  claims nothing.
  """
  @spec claim_devices(DeploymentGroup.t(), DeploymentWorkflowStep.t()) :: non_neg_integer()
  def claim_devices(_deployment_group, %DeploymentWorkflowStep{type: :approval_required}), do: 0

  def claim_devices(deployment_group, step) do
    case remaining_match_limit(step) do
      0 ->
        0

      remaining ->
        now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

        entries =
          deployment_group
          |> unclaimed_matching_devices_query(step)
          |> maybe_limit(remaining)
          |> select([device: d], d.id)
          |> Repo.all()
          |> Enum.map(&%{deployment_workflow_step_id: step.id, device_id: &1, inserted_at: now, updated_at: now})

        {claimed, _} = Repo.insert_all(@join_table, entries, on_conflict: :nothing)

        claimed
    end
  end

  @doc """
  How many devices a step has claimed.
  """
  @spec claimed_device_count(DeploymentWorkflowStep.t()) :: non_neg_integer()
  def claimed_device_count(step) do
    @join_table
    |> from(as: :step_device)
    |> where([step_device: sd], sd.deployment_workflow_step_id == ^step.id)
    |> Repo.aggregate(:count)
  end

  @doc """
  How many of a step's devices are not yet running the release's firmware.

  Deleted devices are left out — one would otherwise hold a step open forever.
  """
  @spec outstanding_device_count(DeploymentGroup.t(), DeploymentWorkflowStep.t()) :: non_neg_integer()
  def outstanding_device_count(deployment_group, step) do
    firmware_uuid = deployment_group.current_release.firmware.uuid

    deployment_group
    |> step_devices_query(step)
    |> where(
      [device: d],
      is_nil(d.firmware_metadata) or fragment("? #>> '{\"uuid\"}'", d.firmware_metadata) != ^firmware_uuid
    )
    |> Repo.aggregate(:count)
  end

  @doc """
  How many of a step's devices have failed to take the update.

  A device counts as failed once it is in the penalty box, which is where
  `NervesHub.Devices.Updates` puts it after `device_failure_threshold` attempts.
  Its own retries have already been spent by that point.
  """
  @spec failed_device_count(DeploymentGroup.t(), DeploymentWorkflowStep.t()) :: non_neg_integer()
  def failed_device_count(deployment_group, step) do
    now = DateTime.utc_now()

    deployment_group
    |> step_devices_query(step)
    |> where([device: d], not is_nil(d.updates_blocked_until) and d.updates_blocked_until > ^now)
    |> Repo.aggregate(:count)
  end

  @doc """
  Whether enough of a step's devices have failed to fail the step.

  A step with no tolerance never fails: that is the trailing `catch_all`, which
  has nothing after it to hold back, and an `approval_required` step, which has
  no devices of its own.
  """
  @spec step_failed?(DeploymentGroup.t(), DeploymentWorkflowStep.t()) :: boolean()
  def step_failed?(deployment_group, step) do
    case failure_limit(step, claimed_device_count(step)) do
      :never -> false
      limit -> failed_device_count(deployment_group, step) >= limit
    end
  end

  @doc """
  How many device failures this step tolerates before it is failed.

  A percentage is of the devices the step claimed, and never rounds down to
  nothing — "5% of 10 devices" means one, not zero.
  """
  @spec failure_limit(DeploymentWorkflowStep.t(), non_neg_integer()) :: pos_integer() | :never
  def failure_limit(%DeploymentWorkflowStep{failure_tolerance: nil}, _claimed), do: :never

  def failure_limit(%DeploymentWorkflowStep{failure_tolerance: %{devices: devices}}, _claimed) when is_integer(devices),
    do: max(devices, 1)

  def failure_limit(%DeploymentWorkflowStep{failure_tolerance: %{percent: percent}}, claimed)
      when is_integer(percent) do
    claimed
    |> Kernel.*(percent)
    |> Kernel./(100)
    |> Float.ceil()
    |> trunc()
    |> max(1)
  end

  def failure_limit(_step, _claimed), do: :never

  # The devices a step claimed that are still part of the deployment group. One
  # that has been moved elsewhere, or deleted, is no longer this step's business
  # and would otherwise hold it open indefinitely.
  defp step_devices_query(deployment_group, step) do
    Device
    |> from(as: :device)
    |> join(:inner, [device: d], sd in ^@join_table,
      on: sd.device_id == d.id and sd.deployment_workflow_step_id == ^step.id,
      as: :step_device
    )
    |> Repo.exclude_deleted()
    |> where([device: d], d.deployment_id == ^deployment_group.id)
  end

  @doc """
  How many more devices a step may have updating at once.
  """
  @spec available_slots(DeploymentWorkflowStep.t()) :: non_neg_integer()
  def available_slots(step) do
    (step.concurrency - FirmwareUpdates.count_inflight_updates_for_workflow_step(step))
    |> max(0)
    |> round()
  end

  @doc """
  Whether a step has done its job and the workflow may move on.

  A `catch_all` never completes. It is the release's steady state: devices keep
  arriving and devices revert, so there is no point at which it is finished. An
  `approval_required` step completes once somebody approves it. Anything else
  completes when every device it claimed is running the release's firmware —
  including when it claimed none, which is how a workflow gets past a stage no
  device matches.
  """
  @spec step_complete?(DeploymentGroup.t(), DeploymentWorkflowStep.t()) :: boolean()
  def step_complete?(_deployment_group, %DeploymentWorkflowStep{type: :catch_all}), do: false

  def step_complete?(_deployment_group, %DeploymentWorkflowStep{type: :approval_required} = step) do
    not is_nil(step.approved_at)
  end

  def step_complete?(deployment_group, step) do
    outstanding_device_count(deployment_group, step) == 0
  end

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

  @doc """
  Record a user's approval of an `approval_required` step.

  Approving only unblocks the step; the coordinator completes it on its next
  pass, which keeps every status change in one place.
  """
  @spec approve_step(DeploymentWorkflowStep.t(), User.t()) :: DeploymentWorkflowStep.t()
  def approve_step(step, user) do
    transition(step, approved_at: now(), approved_by_id: user.id)
  end

  @doc """
  Fail a step, stopping the workflow where it stands.

  Nothing further is scheduled until somebody retries or skips it. That is the
  point of a staged rollout: the stage that went wrong should not hand on to the
  next one.
  """
  @spec fail_step(DeploymentWorkflowStep.t()) :: DeploymentWorkflowStep.t()
  def fail_step(step) do
    transition(step, status: :error, finished_at: now())
  end

  @doc """
  Whether a step can be skipped.

  The trailing `catch_all` cannot: nothing follows it to pick its devices up, so
  skipping it would quietly end the release rather than move it along. A step
  that has already finished has nothing to skip.
  """
  @spec skippable?(DeploymentWorkflowStep.t()) :: boolean()
  def skippable?(%DeploymentWorkflowStep{type: :catch_all}), do: false
  def skippable?(%DeploymentWorkflowStep{status: status}), do: status in [:waiting, :in_progress, :error]

  @doc """
  Whether a step can be retried. Only a failed one has anything to retry.
  """
  @spec retryable?(DeploymentWorkflowStep.t()) :: boolean()
  def retryable?(%DeploymentWorkflowStep{status: status}), do: status == :error

  @doc """
  Skip a step.

  Its claim on its devices is released, so a later step — usually the trailing
  `catch_all` — picks them up rather than leaving them stranded on old firmware.
  This is the way out of a stage held open by a device that will not come back.
  """
  @spec skip_step(DeploymentWorkflowStep.t(), User.t()) :: {:ok, DeploymentWorkflowStep.t()} | {:error, :not_skippable}
  def skip_step(step, user) do
    if skippable?(step) do
      _ = release_claimed_devices(step)

      {:ok, transition(step, status: :skipped, skipped_at: now(), skipped_by_id: user.id)}
    else
      {:error, :not_skippable}
    end
  end

  @doc """
  Retry a failed step.

  The devices that failed are let out of the penalty box and their attempts
  cleared, because leaving them there would mean the retry failed again
  immediately on the same evidence. The step goes back to running and is
  scheduled again on the orchestrator's next pass.
  """
  @spec retry_step(DeploymentGroup.t(), DeploymentWorkflowStep.t(), User.t()) ::
          {:ok, DeploymentWorkflowStep.t()} | {:error, :not_retryable}
  def retry_step(deployment_group, step, user) do
    if retryable?(step) do
      {released, _} =
        deployment_group
        |> step_devices_query(step)
        |> exclude(:order_by)
        |> Repo.update_all(set: [updates_blocked_until: nil, update_attempts: []])

      Logger.info("Workflow step retried",
        deployment_id: deployment_group.id,
        step_number: step.number,
        user_id: user.id,
        devices_released: released
      )

      {:ok, transition(step, status: :in_progress, finished_at: nil, started_at: now())}
    else
      {:error, :not_retryable}
    end
  end

  defp release_claimed_devices(step) do
    @join_table
    |> from(as: :step_device)
    |> where([step_device: sd], sd.deployment_workflow_step_id == ^step.id)
    |> Repo.delete_all()
  end

  # Devices in the deployment group that match the step and have not already been
  # claimed by one of the release's steps.
  defp unclaimed_matching_devices_query(deployment_group, step) do
    deployment_group
    |> matching_devices_query(step)
    |> where([device: d], d.id not in subquery(claimed_device_ids_query(step.deployment_release_id)))
  end

  defp matching_devices_query(deployment_group, %DeploymentWorkflowStep{type: :catch_all}) do
    deployment_group_devices_query(deployment_group)
  end

  defp matching_devices_query(deployment_group, %DeploymentWorkflowStep{matching_conditions: nil}) do
    deployment_group_devices_query(deployment_group)
  end

  defp matching_devices_query(deployment_group, %DeploymentWorkflowStep{matching_conditions: conditions}) do
    deployment_group
    |> deployment_group_devices_query()
    |> maybe_match_tags(conditions.tags)
    |> maybe_match_network_interfaces(conditions.network_interfaces)
  end

  defp deployment_group_devices_query(deployment_group) do
    Device
    |> from(as: :device)
    |> where([device: d], d.deployment_id == ^deployment_group.id)
    |> Repo.exclude_deleted()
    # Claiming happens once and then sticks, so pick in a stable order rather than
    # by anything that moves around, such as connection recency.
    |> order_by([device: d], asc: d.id)
  end

  defp maybe_match_tags(query, tags) when tags in [nil, []], do: query

  # `@>` is "contains all of", so a device has to carry every tag the step asks
  # for, matching how a deployment group's `release_tags` are applied.
  defp maybe_match_tags(query, tags) do
    where(query, [device: d], fragment("? @> ?", d.tags, ^tags))
  end

  defp maybe_match_network_interfaces(query, interfaces) when interfaces in [nil, []], do: query

  # The interface comes off the most recent connection, which outlives the
  # connection itself, so a device that is currently offline still matches.
  defp maybe_match_network_interfaces(query, interfaces) do
    query
    |> join(:inner, [device: d], lc in assoc(d, :latest_connection), as: :latest_connection)
    |> where([latest_connection: lc], lc.network_interface in ^interfaces)
  end

  defp claimed_device_ids_query(deployment_release_id) do
    @join_table
    |> from(as: :step_device)
    |> join(:inner, [step_device: sd], s in DeploymentWorkflowStep,
      on: s.id == sd.deployment_workflow_step_id,
      as: :step
    )
    |> where([step: s], s.deployment_release_id == ^deployment_release_id)
    |> select([step_device: sd], sd.device_id)
  end

  # A catch_all takes everyone left, so it has no limit to run out of.
  defp remaining_match_limit(%DeploymentWorkflowStep{type: :catch_all}), do: :unlimited
  defp remaining_match_limit(%DeploymentWorkflowStep{matching_conditions: nil}), do: :unlimited

  defp remaining_match_limit(%DeploymentWorkflowStep{matching_conditions: %{match_limit: nil}}), do: :unlimited

  defp remaining_match_limit(%DeploymentWorkflowStep{matching_conditions: %{match_limit: limit}} = step) do
    max(limit - claimed_device_count(step), 0)
  end

  defp maybe_limit(query, :unlimited), do: query
  defp maybe_limit(query, count), do: limit(query, ^count)

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
