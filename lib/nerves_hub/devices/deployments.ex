defmodule NervesHub.Devices.Deployments do
  @moduledoc """
  Context for a device's relationship to its deployment group.

  Covers deployment group membership matching (does a device satisfy a
  deployment group's version and tag conditions?), assigning and clearing a
  device's deployment group, and the per-deployment device counts used to
  summarize a deployment group's rollout progress.
  """

  import Ecto.Query

  alias NervesHub.DeploymentOrchestratorEvents
  alias NervesHub.DeviceEvents
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareMetadata
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Repo

  @type firmware_id :: binary()
  @type source_firmware_id() :: firmware_id()
  @type target_firmware_id() :: firmware_id()

  @doc """
  The firmware pairs a deployment group's devices need deltas for: each device's
  running firmware, and the firmware of the release it is updating to next (see
  `NervesHub.ManagedDeployments.join_target_release/1`).

  Given device ids, only those devices' pairs, so a move asks about the devices
  it just moved rather than the whole group again. The ids must be devices
  already in the group, as a move's are.
  """
  @spec get_device_firmware_for_delta_generation_by_deployment_group(integer(), [pos_integer()] | :all) ::
          list({source_firmware_id(), target_firmware_id()})
  def get_device_firmware_for_delta_generation_by_deployment_group(deployment_id, device_ids \\ :all) do
    Device
    |> from(as: :device)
    |> where_in_group(deployment_id, device_ids)
    # Deleted firmware has no file left to build a delta from. Its row can also
    # share a uuid with the live firmware a device is already on, which would
    # pair the device with the firmware it is running.
    |> join(:inner, [device: d], f in Firmware,
      on:
        f.product_id == d.product_id and f.uuid == fragment("?->>'uuid'", d.firmware_metadata) and
          is_nil(f.deleted_at),
      as: :firmware
    )
    |> ManagedDeployments.join_target_release(deployment_id)
    # Devices already on the firmware they are headed for need no delta
    |> where([firmware: f, target_release: tr], f.id != tr.firmware_id)
    |> select([firmware: f, target_release: tr], {f.id, tr.firmware_id})
    |> distinct(true)
    |> Repo.all()
  end

  defp where_in_group(query, deployment_id, :all) do
    query
    |> join(:inner, [device: d], dg in DeploymentGroup, on: dg.id == d.deployment_id, as: :deployment_group)
    |> where([deployment_group: dg], dg.id == ^deployment_id)
  end

  # Found by id alone. Postgres's statistics on a group's devices are from
  # before a move began, so with `deployment_id` in the query too it expects
  # an empty group, reaches the ids through every device the move has already
  # added, and each chunk takes longer than the last. Measured on a
  # 190,000-device move: up to 2.4s per chunk and 43s in all that way, against
  # at most 19ms per chunk and 0.5s in all by id.
  defp where_in_group(query, deployment_id, device_ids) do
    query
    |> join(:inner, [], dg in DeploymentGroup, on: dg.id == ^deployment_id, as: :deployment_group)
    |> where([device: d], d.id in ^device_ids)
  end

  @doc """
  Returns true if Version.match? and all deployment tags are in device tags.
  """
  def matches_deployment_group?(
        %Device{tags: tags, firmware_metadata: %FirmwareMetadata{version: version}},
        %DeploymentGroup{conditions: %{version: requirement, tags: dep_tags}}
      ) do
    if version_match?(version, requirement) and tags_match?(tags, dep_tags) do
      true
    else
      false
    end
  end

  def matches_deployment_group?(_, _), do: false

  @spec update_deployment_group(Device.t(), DeploymentGroup.t()) :: Device.t()
  # No-op if the deployment group ID matches the current deployment ID
  def update_deployment_group(%{deployment_id: deployment_id} = device, %{id: deployment_id}) do
    device
  end

  def update_deployment_group(device, deployment_group) do
    # Use a transaction to ensure device update and delta generation happen atomically
    # This prevents race condition: when the transaction commits, both the device's new
    # deployment_id and any firmware_delta rows (with :processing status) become visible
    # simultaneously, preventing the orchestrator from scheduling a full update when a delta
    # is being prepared
    {:ok, device} =
      Repo.transact(fn ->
        # Update the device's deployment group first
        updated_device =
          device
          |> Device.update_deployment_group(deployment_group)
          |> Repo.update!()

        # Then queue delta generation for any new device firmware combinations
        # This will pick up the newly added device's firmware
        _ = ManagedDeployments.trigger_delta_generation_for_deployment_group(deployment_group, [updated_device.id])

        {:ok, updated_device}
      end)

    # notify the device about its assigned deployment group changing
    DeviceEvents.deployment_assigned(device)

    # let the orchestrator know that a device has been added to the deployment group
    DeploymentOrchestratorEvents.device_added(device)

    Map.put(device, :deployment_group, deployment_group)
  end

  @spec clear_deployment_group(Device.t()) :: Device.t()
  def clear_deployment_group(device) do
    device =
      device
      |> Device.clear_deployment_group()
      |> Repo.update!()

    DeviceEvents.deployment_cleared(device)

    Map.put(device, :deployment_group, nil)
  end

  def deployment_device_online(%DeviceInfo{deployment_id: nil}) do
    :ok
  end

  def deployment_device_online(device_info) do
    firmware_uuid = if(device_info.firmware_metadata, do: device_info.firmware_metadata.uuid)

    payload = %{
      update_mode: device_info.device_update_mode,
      updates_blocked_until: device_info.device_updates_blocked_until,
      firmware_uuid: firmware_uuid
    }

    DeploymentOrchestratorEvents.device_online(device_info, payload)

    :ok
  end

  def up_to_date_count(%DeploymentGroup{} = deployment_group) do
    Device
    |> where([d], d.deployment_id == ^deployment_group.id)
    |> where([d], d.update_mode == :automatic)
    |> where([d], d.firmware_metadata["uuid"] == ^deployment_group.current_release.firmware.uuid)
    |> Repo.exclude_deleted()
    |> Repo.aggregate(:count)
  end

  @spec updating_count(DeploymentGroup.t()) :: term() | nil
  def updating_count(%DeploymentGroup{id: id}) do
    InflightUpdate
    |> where([ifu], ifu.deployment_id == ^id)
    |> Repo.aggregate(:count)
  end

  @spec waiting_for_update_count(DeploymentGroup.t()) :: term() | nil
  def waiting_for_update_count(%DeploymentGroup{} = deployment_group) do
    Device
    |> where([d], d.deployment_id == ^deployment_group.id)
    |> where([d], d.update_mode == :automatic)
    |> where(
      [d],
      is_nil(d.firmware_metadata) or
        d.firmware_metadata["uuid"] != ^deployment_group.current_release.firmware.uuid
    )
    |> Repo.exclude_deleted()
    |> Repo.aggregate(:count)
  end

  @spec updates_disabled_count(DeploymentGroup.t()) :: non_neg_integer()
  def updates_disabled_count(%DeploymentGroup{id: id}) do
    Device
    |> where([d], d.deployment_id == ^id)
    |> where([d], d.update_mode == :off)
    |> Repo.exclude_deleted()
    |> Repo.aggregate(:count)
  end

  @spec in_penalty_box_count(DeploymentGroup.t(), DateTime.t()) :: non_neg_integer()
  def in_penalty_box_count(%DeploymentGroup{id: id}, now \\ DateTime.utc_now()) do
    Device
    |> where([d], d.deployment_id == ^id)
    |> where([d], not is_nil(d.updates_blocked_until) and d.updates_blocked_until > ^now)
    |> Repo.exclude_deleted()
    |> Repo.aggregate(:count)
  end

  @doc """
  Removes the deployment group's devices that don't match its conditions.
  `matched_devices` is a query for the devices to keep, the one from
  `ManagedDeployments.matched_devices_query(deployment_group, in_deployment: true)`.
  Postgres compares against it directly, so the ids to keep are never loaded.
  Only the group's own devices, in its product, are removed.

  Devices are removed 5,000 to a statement, each committed on its own, so a
  large group's rows aren't all locked until the last is written. The return
  is how many were removed. Once every chunk is in, the removed devices are
  told in batches, from a background task, so this returns before they've all
  heard. If a chunk fails, the ones before it stay removed, their devices are
  still told, and the failure is raised for the caller to report.

  matched = ManagedDeployments.matched_devices_query(deployment_group, in_deployment: true)
  remove_unmatched_devices_from_deployment_group(matched, deployment_group)
  > {:ok, %{updated: 2}}
  """
  @spec remove_unmatched_devices_from_deployment_group(Ecto.Query.t(), DeploymentGroup.t()) ::
          {:ok, %{updated: non_neg_integer()}}
  def remove_unmatched_devices_from_deployment_group(%Ecto.Query{} = matched_devices, deployment_group) do
    unmatched =
      Device
      |> Repo.exclude_deleted()
      |> where([d], d.deployment_id == ^deployment_group.id)
      |> where([d], d.product_id == ^deployment_group.product_id)
      |> where_not_kept(matched_devices)

    {removed, failure} =
      unmatched
      |> unmatched_id_pages()
      |> Enum.reduce_while({[], nil}, fn page, {removed, nil} ->
        try do
          {:cont, {[remove_chunk(page, deployment_group.id) | removed], nil}}
        rescue
          error -> {:halt, {removed, {error, __STACKTRACE__}}}
        end
      end)

    removed_device_ids = removed |> Enum.reverse() |> List.flatten()

    # Only the removed devices have anything to hear about. The ones kept are
    # still where they were.
    :ok = DeviceEvents.deployment_changed_for_many(removed_device_ids, nil)

    case failure do
      nil -> {:ok, %{updated: length(removed_device_ids)}}
      {error, stacktrace} -> reraise error, stacktrace
    end
  end

  @remove_chunk_size 5_000

  # The unmatched devices' ids, a page at a time, each page starting after the
  # last id of the one before, so a page never scans again over the rows
  # earlier pages cleared.
  defp unmatched_id_pages(unmatched) do
    Stream.unfold(0, fn
      :done ->
        nil

      after_id ->
        page =
          unmatched
          |> where([d], d.id > ^after_id)
          |> order_by([d], asc: d.id)
          |> limit(@remove_chunk_size)
          |> select([d], d.id)
          |> Repo.all(timeout: to_timeout(minute: 2))

        case page do
          [] -> nil
          page when length(page) < @remove_chunk_size -> {page, :done}
          page -> {page, List.last(page)}
        end
    end)
  end

  # The group is checked again on the row being updated, so a device moved
  # elsewhere since its page was read keeps its new group.
  defp remove_chunk(ids, deployment_id) do
    {_count, removed} =
      Device
      |> where([d], d.id in ^ids)
      |> where([d], d.deployment_id == ^deployment_id)
      |> select([d], d.id)
      |> Repo.update_all([set: [deployment_id: nil]], timeout: to_timeout(minute: 2))

    removed
  end

  defp where_not_kept(query, kept) do
    where(query, [d], d.id not in subquery(select(kept, [k], k.id)))
  end

  defp version_match?(_vsn, ""), do: true

  defp version_match?(version, requirement) do
    Version.match?(version, requirement)
  end

  defp tags_match?(nil, deployment_group_tags), do: tags_match?([], deployment_group_tags)
  defp tags_match?(device_tags, nil), do: tags_match?(device_tags, [])

  defp tags_match?(device_tags, deployment_group_tags) do
    Enum.all?(deployment_group_tags, fn tag -> tag in device_tags end)
  end
end
