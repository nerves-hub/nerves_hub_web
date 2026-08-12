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

  @spec get_device_firmware_for_delta_generation_by_deployment_group(binary()) ::
          list({source_firmware_id(), target_firmware_id()})
  def get_device_firmware_for_delta_generation_by_deployment_group(deployment_id) do
    DeploymentGroup
    |> where([dep], dep.id == ^deployment_id)
    |> join(:inner, [dep], dev in Device, on: dev.deployment_id == dep.id)
    |> join(:inner, [dep], cr in assoc(dep, :current_release))
    |> join(:inner, [_, dev], f in Firmware, on: f.uuid == fragment("?.firmware_metadata->>'uuid'", dev))
    # Exclude the current firmware, we don't need to generate that one
    |> where([_, _, cr, f], f.id != cr.firmware_id)
    |> select([_, _, cr, f], {f.id, cr.firmware_id})
    |> distinct(true)
    |> Repo.all()
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
        _ = ManagedDeployments.trigger_delta_generation_for_deployment_group(deployment_group)

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
      updates_enabled: device_info.device_updates_enabled,
      updates_blocked_until: device_info.device_updates_blocked_until,
      firmware_uuid: firmware_uuid
    }

    DeploymentOrchestratorEvents.device_online(device_info, payload)

    :ok
  end

  def up_to_date_count(%DeploymentGroup{} = deployment_group) do
    Device
    |> where([d], d.deployment_id == ^deployment_group.id)
    |> where([d], d.updates_enabled == true)
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
    |> where([d], d.updates_enabled == true)
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
    |> where([d], d.updates_enabled == false)
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
  Removes unmatched devices from deployment group. The given device ids are
  assumed to be ids of devices that "match" a deployment group's conditions,
  e.g. devices from ManagedDeployments.matched_device_ids/2. Devices are
  fetched by their id and also filtered by the deployment group's id and
  product id.

  `Repo.update_all()` is used to update the rows. The return informs how
  many rows were updated and how many were ignored because of a problem.

  remove_unmatched_devices_from_deployment_group([1, 2, 3], deployment_group)
  > {:ok, %{updated: 3, ignored: 0}}
  """
  @spec remove_unmatched_devices_from_deployment_group([non_neg_integer()], DeploymentGroup.t()) ::
          {:ok, %{updated: non_neg_integer(), ignored: non_neg_integer()}}
  def remove_unmatched_devices_from_deployment_group(matched_device_ids, deployment_group) do
    {devices_updated_count, _} =
      Device
      |> Repo.exclude_deleted()
      |> where([d], d.deployment_id == ^deployment_group.id)
      |> where([d], d.product_id == ^deployment_group.product_id)
      |> where([d], d.id not in ^matched_device_ids)
      |> Repo.update_all([set: [deployment_id: nil]], timeout: to_timeout(minute: 2))

    :ok = Enum.each(matched_device_ids, &DeviceEvents.updated(%Device{id: &1}))

    {:ok,
     %{
       updated: devices_updated_count,
       ignored: length(matched_device_ids) - devices_updated_count
     }}
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
