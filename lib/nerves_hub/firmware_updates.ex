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
  alias NervesHub.Devices.UpdateStats
  alias NervesHub.Firmwares.FirmwareMetadata
  alias NervesHub.Helpers.Logging
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.Repo

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

        clear_inflight_update(device_id)
      end,
      preload: :deployment
    )
  end

  def status_update("rescheduled", device_id, %{"delay_for" => delay_for} = info, _opts) do
    blocked_until = NaiveDateTime.utc_now(:second) |> NaiveDateTime.add(delay_for, :millisecond)
    payload = %{blocked_until: blocked_until, reason: info["reason"]}

    callback = fn device ->
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
    do_status_update(device_id, status, info, fn %{inflight_update: ifu} ->
      if to_string(ifu.status) != status or should_persist?(ifu) do
        InflightUpdate.update_status_changeset(ifu, status, info["progress"])
        |> Repo.update!()
      end
    end)
  end

  def status_update(status, device_id, info, _opts) do
    do_status_update(device_id, status, info, fn device ->
      InflightUpdate.update_status_changeset(device.inflight_update, status, nil)
      |> Repo.update!()
    end)
  end

  defp do_status_update(device_id, status, payload, update_fn, opts \\ []) do
    Repo.transaction(fn ->
      device =
        fetch_device(device_id, opts)
        |> maybe_update_update_attempts()

      update_fn.(device)

      broadcast_firmware_update_status!(device_id, status, payload)

      {:ok, device}
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

  @spec delete_expired_inflight_updates() :: integer
  def delete_expired_inflight_updates() do
    {counts, results} =
      InflightUpdate
      |> join(:inner, [iu], d in assoc(iu, :device))
      |> where([iu], iu.updated_at < fragment("NOW() - INTERVAL '30 minutes'"))
      |> select([iu, d], %{device_id: d.id})
      |> Repo.delete_all()

    Enum.each(results, fn result ->
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

  defp fetch_device(device_id, opts) do
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
    |> select([d, ifu], [:id, :identifier, :product_id, :org_id, :update_attempts, :updates_blocked_until])
    |> where([d], d.id == ^device_id)
    |> Repo.one!()
    |> case do
      %{inflight_update: nil} = device ->
        inflight_update =
          InflightUpdate.empty_requested_changeset(device.id)
          |> Repo.insert!()
          # the record was built here rather than by the query above, so the
          # association is unloaded. It has no deployment_id, so nil is correct.
          |> Map.put(:deployment_group, nil)

        Map.put(device, :inflight_update, inflight_update)

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
