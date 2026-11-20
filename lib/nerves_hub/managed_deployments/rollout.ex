defmodule NervesHub.ManagedDeployments.Rollout do
  @moduledoc """
  How far a deployment group's current release has got: where each of the
  group's devices stands with it, how far each workflow step has come, and which
  devices it hasn't reached.

  The deployment groups list shows this for every group at once, so the counts
  are taken for a list of groups in a fixed number of queries rather than a few
  per group.

  ## Where a device stands

  Every device in a group is in exactly one of these, checked in this order:

    * `:updated` - it runs the release's firmware.
    * `:updates_off` - its updates are turned off, so it never gets the release.
    * `:updating` - it is taking the update now.
    * `:penalty_box` - it failed too many times in a row and is held back for a
      while. A workflow step counts these devices as failed.
    * `:failed` - its last attempt failed and it will be offered the update
      again.
    * `:waiting` - none of the above: its turn hasn't come, or the group is
      paused.
  """

  import Ecto.Query

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.Repo

  @step_devices "deployment_workflow_steps_devices"

  @states [:updated, :updates_off, :updating, :penalty_box, :failed, :waiting]

  @type state :: :updated | :updates_off | :updating | :penalty_box | :failed | :waiting

  @typedoc "What a group's rollout adds up to; see `status/4`."
  @type status :: :paused | :stopped | :awaiting_approval | :no_devices | :up_to_date | :rolling_out

  @type counts :: %{
          required(:total) => non_neg_integer(),
          required(state()) => non_neg_integer()
        }

  @type step_counts :: %{
          devices: non_neg_integer(),
          updated: non_neg_integer(),
          failed: non_neg_integer()
        }

  @type unreached :: %{
          device: Device.t(),
          state: :penalty_box | :failed | :updates_off,
          step: DeploymentWorkflowStep.t() | nil
        }

  @doc """
  Every state a device can be in, in the order they are checked.
  """
  @spec states() :: [state(), ...]
  def states(), do: @states

  @doc """
  An empty set of counts, for a group with no devices.
  """
  @spec empty_counts() :: counts()
  def empty_counts(), do: Map.new([{:total, 0} | Enum.map(@states, &{&1, 0})])

  @doc """
  How many of each group's devices are in each state, keyed by group id.

  A group with no devices gets `empty_counts/0`.
  """
  @spec counts([DeploymentGroup.t()], DateTime.t()) :: %{pos_integer() => counts()}
  def counts(deployment_groups, now \\ DateTime.utc_now())

  def counts([], _now), do: %{}

  def counts(deployment_groups, now) do
    ids = Enum.map(deployment_groups, & &1.id)

    states =
      devices_with_current_firmware()
      |> join(:left, [device: d, deployment_group: dg], i in InflightUpdate,
        on: i.device_id == d.id and i.deployment_id == dg.id,
        as: :inflight
      )
      |> where([device: d], d.deployment_id in ^ids)
      |> Repo.exclude_deleted()
      |> select([device: d, firmware: f, inflight: i], %{
        deployment_id: d.deployment_id,
        state:
          fragment(
            """
            CASE
              WHEN ? ->> 'uuid' = ? THEN 'updated'
              WHEN ? = 'off' THEN 'updates_off'
              WHEN ? IS NOT NULL THEN 'updating'
              WHEN ? > ? THEN 'penalty_box'
              WHEN ? > 0 THEN 'failed'
              ELSE 'waiting'
            END
            """,
            d.firmware_metadata,
            f.uuid,
            d.update_mode,
            i.id,
            d.updates_blocked_until,
            ^now,
            d.consecutive_failed_updates
          )
      })

    found =
      states
      |> subquery()
      |> group_by([s], [s.deployment_id, s.state])
      |> select([s], {s.deployment_id, s.state, count()})
      |> Repo.all()
      |> Enum.reduce(%{}, fn {id, state, count}, acc ->
        state = String.to_existing_atom(state)

        acc
        |> Map.put_new(id, empty_counts())
        |> update_in([id], &%{&1 | state => count, total: &1.total + count})
      end)

    Map.new(ids, &{&1, Map.get(found, &1, empty_counts())})
  end

  @doc """
  How far each step of the groups' current releases has come, keyed by step id.

  A step's devices are the ones it claimed. The trailing catch-all claims none,
  so its devices are the group's devices no step of the release has claimed.
  An approval step has no devices of its own.

  `failed` counts devices in the penalty box, which is what a step counts
  against its failure tolerance.
  """
  @spec step_counts([DeploymentGroup.t()], DateTime.t()) :: %{pos_integer() => step_counts()}
  def step_counts(deployment_groups, now \\ DateTime.utc_now())

  def step_counts([], _now), do: %{}

  def step_counts(deployment_groups, now) do
    ids = Enum.map(deployment_groups, & &1.id)
    release_ids = Enum.map(deployment_groups, & &1.current_deployment_release_id)

    claimed =
      devices_with_current_firmware()
      |> join(:inner, [device: d], sd in @step_devices, on: sd.device_id == d.id, as: :step_device)
      |> join(:inner, [step_device: sd, release: r], s in DeploymentWorkflowStep,
        on: s.id == sd.deployment_workflow_step_id and s.deployment_release_id == r.id,
        as: :step
      )
      |> where([deployment_group: dg], dg.id in ^ids)
      |> where([device: d], is_nil(d.deleted_at))
      |> group_by([step: s], s.id)
      |> select([step: s, device: d, firmware: f], %{
        id: s.id,
        devices: count(d.id),
        updated: filter(count(d.id), fragment("? ->> 'uuid' = ?", d.firmware_metadata, f.uuid)),
        failed: filter(count(d.id), d.updates_blocked_until > ^now)
      })
      |> Repo.all()
      |> Map.new(&{&1.id, Map.delete(&1, :id)})

    claims =
      @step_devices
      |> from(as: :step_device)
      |> join(:inner, [step_device: sd], s in DeploymentWorkflowStep,
        on: s.id == sd.deployment_workflow_step_id,
        as: :step
      )
      |> where([step: s], s.deployment_release_id in ^release_ids)
      |> select([step_device: sd, step: s], %{device_id: sd.device_id, release_id: s.deployment_release_id})

    unclaimed =
      devices_with_current_firmware()
      |> join(:left, [device: d, deployment_group: dg], c in subquery(claims),
        on: c.device_id == d.id and c.release_id == dg.current_deployment_release_id,
        as: :claim
      )
      |> where([deployment_group: dg], dg.id in ^ids)
      |> where([claim: c], is_nil(c.device_id))
      |> Repo.exclude_deleted()
      |> group_by([deployment_group: dg], dg.id)
      |> select([deployment_group: dg, device: d, firmware: f], %{
        id: dg.id,
        devices: count(d.id),
        updated: filter(count(d.id), fragment("? ->> 'uuid' = ?", d.firmware_metadata, f.uuid)),
        failed: filter(count(d.id), d.updates_blocked_until > ^now)
      })
      |> Repo.all()
      |> Map.new(&{&1.id, Map.delete(&1, :id)})

    for dg <- deployment_groups, step <- dg.current_release.steps, into: %{} do
      counts =
        case step.type do
          :approval_required -> empty_step_counts()
          :catch_all -> Map.get(unclaimed, dg.id, empty_step_counts())
          :update_devices -> Map.get(claimed, step.id, empty_step_counts())
        end

      {step.id, counts}
    end
  end

  defp empty_step_counts(), do: %{devices: 0, updated: 0, failed: 0}

  # Devices in a deployment group, with the group, its current release and that
  # release's firmware joined as `:deployment_group`, `:release` and `:firmware`.
  defp devices_with_current_firmware() do
    Device
    |> from(as: :device)
    |> join(:inner, [device: d], dg in DeploymentGroup, on: dg.id == d.deployment_id, as: :deployment_group)
    |> join(:inner, [deployment_group: dg], r in DeploymentRelease,
      on: r.id == dg.current_deployment_release_id,
      as: :release
    )
    |> join(:inner, [release: r], f in Firmware, on: f.id == r.firmware_id, as: :firmware)
  end

  @doc """
  The group's devices the release hasn't reached and won't without help: those
  in the penalty box, those whose last attempt failed, and those with updates
  turned off, in that order. Each comes with the release step it belongs to,
  which for a device no step claimed is the catch-all, if there is one.

  Returns at most `limit` of them, along with how many there are in all.
  """
  @spec unreached(DeploymentGroup.t(), pos_integer(), DateTime.t()) :: {[unreached()], non_neg_integer()}
  def unreached(deployment_group, limit, now \\ DateTime.utc_now()) do
    %{current_release: %{firmware: firmware, steps: steps}} = deployment_group

    query =
      Device
      |> from(as: :device)
      |> where([device: d], d.deployment_id == ^deployment_group.id)
      |> where(
        [device: d],
        is_nil(d.firmware_metadata) or fragment("? ->> 'uuid'", d.firmware_metadata) != ^firmware.uuid
      )
      |> where(
        [device: d],
        d.update_mode == :off or d.updates_blocked_until > ^now or d.consecutive_failed_updates > 0
      )
      |> where([device: d], d.id not in subquery(updating_device_ids(deployment_group)))
      |> Repo.exclude_deleted()

    total = Repo.aggregate(query, :count)

    rows =
      query
      |> join(:left, [device: d], c in subquery(release_claims(deployment_group)),
        on: c.device_id == d.id,
        as: :claim
      )
      |> order_by([device: d],
        asc:
          fragment(
            "CASE WHEN ? = 'off' THEN 2 WHEN ? > ? THEN 0 ELSE 1 END",
            d.update_mode,
            d.updates_blocked_until,
            ^now
          ),
        desc: d.consecutive_failed_updates,
        asc: d.identifier
      )
      |> limit(^limit)
      |> select([device: d, claim: c], {d, c.step_id})
      |> Repo.all()

    steps_by_id = Map.new(steps, &{&1.id, &1})
    catch_all = Enum.find(steps, &(&1.type == :catch_all))

    unreached =
      Enum.map(rows, fn {device, step_id} ->
        step = if step_id, do: Map.get(steps_by_id, step_id), else: catch_all

        %{device: device, state: unreached_state(device, now), step: step}
      end)

    {unreached, total}
  end

  defp unreached_state(%Device{update_mode: :off}, _now), do: :updates_off

  defp unreached_state(%Device{updates_blocked_until: %DateTime{} = until}, now) do
    if DateTime.after?(until, now), do: :penalty_box, else: :failed
  end

  defp unreached_state(_device, _now), do: :failed

  defp updating_device_ids(deployment_group) do
    InflightUpdate
    |> where([i], i.deployment_id == ^deployment_group.id)
    |> select([i], i.device_id)
  end

  # A device belongs to one step of a release, so this has a row per device at
  # most.
  defp release_claims(deployment_group) do
    @step_devices
    |> from(as: :step_device)
    |> join(:inner, [step_device: sd], s in DeploymentWorkflowStep,
      on: s.id == sd.deployment_workflow_step_id,
      as: :step
    )
    |> where([step: s], s.deployment_release_id == ^deployment_group.current_deployment_release_id)
    |> select([step_device: sd, step: s], %{device_id: sd.device_id, step_id: s.id})
  end

  @doc """
  What a group's rollout needs from someone, if anything, given its counts and
  the step it is stopped or waiting on.

    * `:paused` - the group is paused, so nothing moves until it is resumed.
    * `:stopped` - a step failed and is waiting to be retried or skipped.
    * `:awaiting_approval` - a step is waiting to be approved.
    * `:no_devices` - the group has no devices.
    * `:up_to_date` - every device that can take the release has it.
    * `:rolling_out` - anything else: the release is on its way.
  """
  @spec status(DeploymentGroup.t(), counts(), DeploymentWorkflowStep.t() | nil, DeploymentWorkflowStep.t() | nil) ::
          status()
  def status(deployment_group, counts, failed_step, awaiting_approval) do
    cond do
      not deployment_group.is_active -> :paused
      failed_step -> :stopped
      awaiting_approval -> :awaiting_approval
      counts.total == 0 -> :no_devices
      counts.updated + counts.updates_off == counts.total -> :up_to_date
      true -> :rolling_out
    end
  end
end
