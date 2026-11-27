defmodule NervesHub.FirmwareUpdates do
  import Ecto.Query

  alias Ecto.Changeset
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.DeploymentOrchestratorEvents
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Devices.PubSub
  alias NervesHub.Devices.UpdateHistory
  alias NervesHub.Devices.UpdateStats
  alias NervesHub.Firmwares.FirmwareMetadata
  alias NervesHub.Helpers.Logging
  alias NervesHub.Integrations
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.Repo
  alias NervesHub.Webhooks.Payloads

  # The shortest time a reschedule blocks a device for, the same minimum
  # nerves_hub_link applies before it sends one. Without it a device asking for
  # no delay would be offered the update again on the next pass.
  @min_reschedule_minutes 5

  @spec firmware_update_successful(Device.t(), FirmwareMetadata.t() | nil) ::
          {:ok, Device.t()} | {:error, Changeset.t()}
  def firmware_update_successful(%Device{firmware_metadata: nil} = device, _previous_metadata) do
    # Nothing meaningful to record — the device joined without a usable
    # firmware uuid (see update_firmware_metadata/4 with nil metadata).
    {:ok, device}
  end

  def firmware_update_successful(device, previous_metadata) do
    :telemetry.execute([:nerves_hub, :devices, :update, :successful], %{count: 1}, %{
      identifier: device.identifier,
      firmware_uuid: device.firmware_metadata.uuid
    })

    Repo.transact(fn ->
      DeviceTemplates.audit_firmware_updated(device)

      device = Repo.preload(device, :inflight_update)

      _ =
        if device.inflight_update do
          if device.inflight_update.deployment_id do
            DeploymentGroup
            |> where([d], d.id == ^device.inflight_update.deployment_id)
            |> Repo.update_all(inc: [current_updated_devices: 1])

            # let the orchestrator know that an inflight update completed
            DeploymentOrchestratorEvents.device_updated(device)
          end

          # Clear the inflight update, no longer inflight!
          Repo.delete(device.inflight_update)
        end

      _ = UpdateStats.log_update(device, previous_metadata)

      _ =
        UpdateHistory.record(device, :succeeded,
          deployment_id: inflight_field(device.inflight_update, :deployment_id),
          source_firmware_uuid: firmware_uuid(previous_metadata),
          target_firmware_uuid: device.firmware_metadata.uuid,
          # The inflight row is written as the update is sent.
          started_at: inflight_field(device.inflight_update, :inserted_at)
        )

      device
      |> Device.clear_updates_information_changeset()
      |> Repo.update()
    end)
  end

  @spec status_update(status :: String.t(), device_id :: pos_integer(), info :: map(), opts :: Keyword.t()) ::
          :ok | {:error, any()}
  def status_update(status, device_id, info \\ %{}, opts \\ [])

  def status_update("ignored", device_id, info, _opts) do
    do_status_update(
      device_id,
      "ignored",
      %{reason: info["reason"]},
      fn device ->
        deployment_group = deployment_group(device)

        _ =
          if deployment_group do
            blocked_for_mins = deployment_group.penalty_timeout_minutes

            blocked_until = DateTime.utc_now(:second) |> DateTime.add(blocked_for_mins, :minute)

            {:ok, _device} = Devices.update_device(device, %{updates_blocked_until: blocked_until})
          end

        DeviceTemplates.audit_firmware_upgrade_ignored(device, deployment_group, info["reason"])

        _ = record_outcome(device, :ignored, info["reason"])

        clear_inflight_update(device_id)
      end,
      preload: :deployment
    )
  end

  # `delay_for` is in minutes, which is what nerves_hub_link sends and what
  # `update_rejected` gives a device back (docs/device_managed_updates.md).
  def status_update("rescheduled", device_id, %{"delay_for" => delay_for} = info, _opts) do
    delay_minutes = max(delay_for, @min_reschedule_minutes)
    blocked_until = NaiveDateTime.utc_now(:second) |> NaiveDateTime.add(delay_minutes, :minute)
    payload = %{blocked_until: blocked_until, reason: info["reason"]}

    callback = fn device ->
      _ = record_outcome(device, :rescheduled, info["reason"])

      :ok = withdraw_update_attempt(device)

      clear_inflight_update(device_id)

      DeviceTemplates.audit_firmware_upgrade_rescheduled(
        device,
        blocked_until,
        info["reason"]
      )

      if deployment_group(device) do
        {:ok, _device} = Devices.update_device(device, %{updates_blocked_until: blocked_until})
      end
    end

    do_status_update(device_id, "rescheduled", payload, callback, preload: :deployment)
  end

  def status_update("failed", device_id, info, _opts) do
    do_status_update(
      device_id,
      "failed",
      %{reason: info["reason"]},
      fn device ->
        _ = record_outcome(device, :failed, info["reason"])

        clear_inflight_update(device_id)

        if deployment_group = deployment_group(device) do
          blocked_for_mins = deployment_group.penalty_timeout_minutes

          blocked_until = DateTime.utc_now(:second) |> DateTime.add(blocked_for_mins, :minute)

          DeviceTemplates.audit_firmware_upgrade_failed(device, info["reason"],
            penalty_timeout_minutes: blocked_for_mins
          )

          {:ok, _device} = Devices.update_device(device, %{updates_blocked_until: blocked_until})
        else
          DeviceTemplates.audit_firmware_upgrade_failed(device, info["reason"])
        end
      end,
      preload: :deployment
    )
  end

  def status_update(status, device_id, info, _opts) when status in ["downloading", "updating"] do
    do_status_update(device_id, status, info, fn %{inflight_update: ifu} = device ->
      # The event follows the row rather than the device: a stage change or
      # once every 15 seconds, not every percent the device reports.
      if to_string(ifu.status) != status or should_persist?(ifu) do
        InflightUpdate.update_status_changeset(ifu, status, info["progress"])
        |> Repo.update!()
        |> dispatch_progress(device)
      end
    end)
  end

  # The inflight row is written before an update is sent, and the device reports
  # `received` before `started`. With no row, `started` is not an update:
  # nerves_hub_link reports it for every download, archives included. Recording
  # one would block updates to the device until it reconnects or the row expires.
  def status_update("started", device_id, info, _opts) do
    record_status(device_id, "started", info, record_missing: false)
  end

  def status_update(status, device_id, info, _opts) do
    record_status(device_id, status, info)
  end

  defp record_status(device_id, status, info, opts \\ []) do
    do_status_update(
      device_id,
      status,
      info,
      fn device ->
        InflightUpdate.update_status_changeset(device.inflight_update, status, nil)
        |> Repo.update!()
        |> dispatch_progress(device)
      end,
      opts
    )
  end

  defp dispatch_progress(inflight_update, device) do
    Integrations.dispatch(device.product_id, "device.firmware_update.progress", fn ->
      Payloads.firmware_update_progress(
        device,
        to_string(inflight_update.status),
        inflight_update.progress,
        inflight_update.firmware_uuid
      )
    end)
  end

  defp do_status_update(device_id, status, payload, update_fn, opts \\ []) do
    Repo.transaction(fn ->
      case fetch_device(device_id, opts) do
        # Only reached with `record_missing: false`
        %{inflight_update: nil} = device ->
          {:ok, device}

        device ->
          device = maybe_update_update_attempts(device)

          update_fn.(device)

          broadcast_firmware_update_status!(device_id, status, payload)

          {:ok, device}
      end
    end)
    |> case do
      {:ok, _device} ->
        :ok

      {:error, reason} ->
        Logging.log_message_to_sentry("Error updating inflight update status", %{reason: reason})
        {:error, reason}
    end
  end

  def update_inflight_update(device_id, status, progress \\ nil, persist_update? \\ true)

  def update_inflight_update(device_id, status, progress, true) do
    updated_at = DateTime.utc_now() |> DateTime.truncate(:second)

    InflightUpdate
    |> where(device_id: ^device_id)
    |> Repo.update_all(set: [status: status, progress: progress, updated_at: updated_at])
    |> case do
      {1, _} -> broadcast_firmware_update_status!(device_id, status, %{"progress" => progress})
      _ -> true
    end

    :ok
  end

  def update_inflight_update(device_id, status, progress, false) do
    broadcast_firmware_update_status!(device_id, status, %{"progress" => progress})
    :ok
  end

  def clear_inflight_update(%DeviceInfo{device_id: id}) do
    clear_inflight_update(id)
  end

  def clear_inflight_update(%Device{id: id}) do
    clear_inflight_update(id)
  end

  def clear_inflight_update(device_id) do
    InflightUpdate
    |> where([iu], iu.device_id == ^device_id)
    |> Repo.delete_all()
  end

  @doc """
  Ends the device's update because it came back without having taken it.

  `clear_inflight_update/1` with a name for what it means. A device that rejoins
  while it is not downloading anything, still running the firmware it had, did
  not do what it was asked — and says nothing about why, which is why this
  outcome has to be inferred here rather than reported like a `failed` or an
  `ignored`. On a fleet that is failing to update it is usually the common case.

  Returns `:ok` whether or not there was an update to end, so a device joining
  with nothing inflight is not an error.

  An update with no firmware is cleared without being recorded. Every update
  sent from here records its firmware, so a row without one is progress the
  device reported on an update the server had already let go of. That update
  ended when the server let it go, so counting this row too would count one
  update twice.
  """
  @spec abandon_inflight_update(Device.t()) :: :ok
  def abandon_inflight_update(%Device{} = device) do
    InflightUpdate
    |> where([iu], iu.device_id == ^device.id)
    |> select([iu], %{deployment_id: iu.deployment_id, firmware_uuid: iu.firmware_uuid})
    |> Repo.delete_all()
    |> case do
      {0, _} ->
        :ok

      {_count, abandoned} ->
        abandoned
        |> Enum.filter(&sent_firmware?(&1.firmware_uuid))
        |> Enum.each(fn inflight_update ->
          UpdateHistory.record(device, :abandoned,
            deployment_id: inflight_update.deployment_id,
            source_firmware_uuid: firmware_uuid(device.firmware_metadata),
            target_firmware_uuid: inflight_update.firmware_uuid
          )
        end)
    end
  end

  @doc """
  Ends every update that has made no progress for 30 minutes, recording each as
  `:expired`, and returns how many it ended.

  An update with no firmware is ended without being recorded, as in
  `abandon_inflight_update/1`.
  """
  @spec delete_expired_inflight_updates() :: integer
  def delete_expired_inflight_updates() do
    {counts, results} =
      InflightUpdate
      |> join(:inner, [iu], d in assoc(iu, :device))
      |> where([iu], iu.updated_at < fragment("NOW() - INTERVAL '30 minutes'"))
      |> select([iu, d], %{
        device_id: d.id,
        org_id: d.org_id,
        product_id: d.product_id,
        # Read straight out of the jsonb rather than loading the embed, so a
        # `DELETE ... RETURNING` hands back a plain string.
        source_firmware_uuid: fragment("? #>> '{\"uuid\"}'", d.firmware_metadata),
        deployment_id: iu.deployment_id,
        target_firmware_uuid: iu.firmware_uuid
      })
      |> Repo.delete_all()

    Enum.each(results, fn result ->
      _ =
        if sent_firmware?(result.target_firmware_uuid) do
          UpdateHistory.record(
            %{id: result.device_id, org_id: result.org_id, product_id: result.product_id},
            :expired,
            deployment_id: result.deployment_id,
            source_firmware_uuid: result.source_firmware_uuid,
            target_firmware_uuid: result.target_firmware_uuid
          )
        end

      update_inflight_update(result.device_id, "expired", nil, false)
    end)

    counts
  end

  @doc """
  The device's update, including one that has just finished.

  Deliberately not filtered to the active statuses: the device page shows the
  outcome of an update from this — "complete, waiting for device to restart" is
  read off a `:completed` row in the moment before it is cleared. Were updates
  kept as history rather than deleted, this would need to become the most recent
  row rather than the only one.
  """
  def inflight_update_for(%Device{id: device_id}) when not is_nil(device_id) do
    InflightUpdate
    |> where([iu], iu.device_id == ^device_id)
    |> Repo.one()
  end

  def inflight_updates_for(%DeploymentGroup{} = deployment_group) do
    InflightUpdate
    |> active()
    |> where([iu], iu.deployment_id == ^deployment_group.id)
    |> preload([:device])
    |> Repo.all()
  end

  @doc """
  Count inflight updates for a deployment group, excluding priority queue updates.
  This ensures normal queue capacity is calculated independently.
  """
  def count_inflight_updates_for(%DeploymentGroup{} = deployment_group) do
    InflightUpdate
    |> active()
    |> where([iu], iu.deployment_id == ^deployment_group.id)
    |> where([iu], iu.priority_queue == false)
    |> Repo.aggregate(:count)
  end

  @doc """
  Count inflight updates for the devices a workflow step has claimed.

  A workflow step paces its own devices, so the deployment group's concurrency is
  not what limits it.
  """
  @spec count_inflight_updates_for_workflow_step(DeploymentWorkflowStep.t()) :: non_neg_integer()
  def count_inflight_updates_for_workflow_step(%DeploymentWorkflowStep{id: step_id}) do
    InflightUpdate
    |> active()
    |> join(:inner, [iu], sd in "deployment_workflow_steps_devices",
      on: sd.device_id == iu.device_id and sd.deployment_workflow_step_id == ^step_id
    )
    |> Repo.aggregate(:count)
  end

  @doc """
  Count inflight updates that are in the priority queue for a deployment group.
  """
  @spec count_inflight_priority_updates_for(DeploymentGroup.t()) :: non_neg_integer()
  def count_inflight_priority_updates_for(%DeploymentGroup{} = deployment_group) do
    InflightUpdate
    |> active()
    |> where([iu], iu.deployment_id == ^deployment_group.id)
    |> where([iu], iu.priority_queue == true)
    |> Repo.aggregate(:count)
  end

  # An update is only "inflight" while it is still going. Rows that have reached
  # an outcome are deleted today, so this matches exactly what it did before —
  # but the queries no longer rely on that.
  defp active(query) do
    where(query, [iu], iu.status in ^InflightUpdate.active_statuses())
  end

  defp broadcast_firmware_update_status!(device_id, status, extra_info) do
    payload = Map.put(extra_info, "stage", status)
    PubSub.broadcast(device_id, "firmware_update_progress", payload)
  end

  defp maybe_update_update_attempts(%{inflight_update: %{status: :requested}} = device) do
    {1, _} =
      Device
      |> where(id: ^device.id)
      |> update(push: [update_attempts: ^DateTime.utc_now(:second)])
      |> Repo.update_all([])

    device
  end

  defp maybe_update_update_attempts(device), do: device

  # A reschedule is not a failed attempt, so it takes back the attempt its offer
  # counted. That is the last one: an offer is only made to a device with nothing
  # inflight, so nothing else counts one while it is open. Left in, three
  # reschedules would put the device in the penalty box for the group's timeout.
  defp withdraw_update_attempt(device) do
    {_count, _} =
      Device
      |> where(id: ^device.id)
      |> where([d], fragment("cardinality(?) > 0", d.update_attempts))
      |> update(set: [update_attempts: fragment("update_attempts[1:cardinality(update_attempts) - 1]")])
      |> Repo.update_all([])

    :ok
  end

  # The device's update ended. Reads the deployment group and the firmware it
  # was being moved to off the inflight row, which every caller is about to
  # delete, and the firmware it is running off the device itself.
  defp record_outcome(device, status, reason) do
    UpdateHistory.record(device, status,
      deployment_id: inflight_field(device.inflight_update, :deployment_id),
      source_firmware_uuid: firmware_uuid(device.firmware_metadata),
      target_firmware_uuid: inflight_field(device.inflight_update, :firmware_uuid),
      reason: reason
    )
  end

  # Total rather than a field access: a device can join with no firmware
  # metadata at all, and an update can be recorded before it has any.
  defp firmware_uuid(%{uuid: uuid}), do: uuid
  defp firmware_uuid(_), do: nil

  # Likewise for the inflight row: a firmware update can succeed without one,
  # when the device took firmware nobody here asked it to take.
  defp inflight_field(nil, _field), do: nil
  defp inflight_field(inflight_update, field), do: Map.get(inflight_update, field)

  # Whether an inflight row is an update this server sent. Every update sent
  # from here records its firmware. A row without one is `fetch_device/2` making
  # room for progress on an update the server lost track of, such as one whose
  # row already expired and was recorded while the device carried on with it.
  # Expiring or abandoning such a row is not a failed update, and counting it
  # would put phantom failures on the device.
  defp sent_firmware?(nil), do: false
  defp sent_firmware?(_firmware_uuid), do: true

  # Records an empty update for a device with none, so progress on an update the
  # server lost track of is still followed. `record_missing: false` leaves it
  # with none.
  defp fetch_device(device_id, opts) do
    record_missing? = Keyword.get(opts, :record_missing, true)

    Device
    |> join(:left, [d], ifu in assoc(d, :inflight_update))
    |> then(fn query ->
      if opts[:preload] == :deployment do
        join(query, :left, [d, ifu], d in assoc(ifu, :deployment_group))
        |> join(:left, [d, ifu, dg], cr in assoc(dg, :current_release))
        |> preload([d, ifu, dg, cr], inflight_update: {ifu, deployment_group: {dg, current_release: cr}})
      else
        preload(query, [d, ifu], inflight_update: ifu)
      end
    end)
    |> select([d, ifu], [
      :id,
      :identifier,
      :product_id,
      :org_id,
      :firmware_metadata,
      :update_attempts,
      :updates_blocked_until
    ])
    |> where([d], d.id == ^device_id)
    |> Repo.one!()
    |> case do
      %{inflight_update: nil} = device when record_missing? ->
        # Another request can be recording an update for this device at the same
        # moment, in a transaction the read above could not see. The insert waits
        # for it to commit and then gives way, and the device is read again with
        # its row, rather than the conflict being raised.
        InflightUpdate.empty_requested_changeset(device.id)
        |> Repo.insert!(on_conflict: :nothing, conflict_target: :device_id)
        |> case do
          %InflightUpdate{id: nil} ->
            fetch_device(device_id, opts)

          inflight_update ->
            # the record was built here rather than by the query above, so the
            # association is unloaded. It has no deployment_id, so nil is correct.
            Map.put(device, :inflight_update, Map.put(inflight_update, :deployment_group, nil))
        end

      device ->
        device
    end
  end

  # Guards against an unloaded association being mistaken for a deployment
  # group, which is truthy and blows up on the first field access.
  defp deployment_group(%{inflight_update: %{deployment_group: %DeploymentGroup{} = deployment_group}}),
    do: deployment_group

  defp deployment_group(_device), do: nil

  defp should_persist?(ifu) do
    some_secs_ago = NaiveDateTime.utc_now() |> NaiveDateTime.add(-15, :second)
    NaiveDateTime.before?(ifu.updated_at, some_secs_ago)
  end
end
