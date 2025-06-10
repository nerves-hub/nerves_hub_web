defmodule NervesHub.Devices.UpdateStats do
  @moduledoc """
  Module for logging and queryingdevice update statistics.
  """

  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares.FirmwareDelta
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Devices.UpdateStat

  import Ecto.Query

  @types [:fwup_full, :fwup_delta]

  @spec stats_by_device(Device.t()) :: [map()]
  def stats_by_device(%Device{} = device) do
    AnalyticsRepo.all(
      from(s in UpdateStat,
        where: s.device_id == ^device.id,
        select: %{
          total_update_bytes: sum(s.update_bytes),
          total_saved_bytes: sum(s.saved_bytes),
          num_updates: fragment("count()")
        }
      )
    )
  end

  @spec stats_by_deployment(DeploymentGroup.t()) :: [map()]
  def stats_by_deployment(deployment_group) do
    AnalyticsRepo.all(
      from(s in UpdateStat,
        where: s.deployment_id == ^deployment_group.id,
        where: s.target_firmware_uuid == ^deployment_group.firmware.uuid,
        group_by: [s.source_firmware_uuid],
        select: %{
          total_update_bytes: sum(s.update_bytes),
          total_saved_bytes: sum(s.saved_bytes),
          num_updates: fragment("count()")
        }
      )
    )
  end

  def total_stats_by_product(product) do
    AnalyticsRepo.all(
      from(s in UpdateStat,
        where: s.product_id == ^product.id,
        select: %{
          total_update_bytes: sum(s.update_bytes),
          total_saved_bytes: sum(s.saved_bytes),
          num_updates: fragment("count()")
        }
      )
    )
  end

  @spec log_full_update(
          Device.t(),
          DeploymentGroup.t()
        ) :: :ok | {:error, Ecto.Changeset.t()}
  def log_full_update(%Device{} = device, %DeploymentGroup{} = deployment_group) do
    log_stat(device, deployment_group, :fwup_full, deployment_group.firmware.size, 0)
  end

  @spec log_delta_update(
          Device.t(),
          DeploymentGroup.t(),
          FirmwareDelta.t()
        ) :: :ok | {:error, Ecto.Changeset.t()}
  def log_delta_update(
        %Device{} = device,
        %DeploymentGroup{} = deployment_group,
        %FirmwareDelta{} = firmware_delta
      ) do
    target_size = deployment_group.firmware.size
    delta_size = Map.get(firmware_delta.upload_metadata, "size", target_size)
    saved = target_size - delta_size
    log_stat(device, deployment_group, :fwup_delta, delta_size, saved)
  end

  defp log_stat(
         %Device{} = device,
         %DeploymentGroup{} = deployment_group,
         type,
         update_bytes,
         saved_bytes
       )
       when type in @types do
    source_uuid =
      case device do
        %{firmware_metadata: %{uuid: source_uuid}} -> source_uuid
        _ -> nil
      end

    changeset =
      UpdateStat.create_changeset(device, deployment_group, %{
        timestamp: DateTime.utc_now(),
        type: Atom.to_string(type),
        source_firmware_uuid: source_uuid,
        target_firmware_uuid: deployment_group.firmware.uuid,
        update_bytes: update_bytes,
        saved_bytes: saved_bytes
      })

    case Ecto.Changeset.apply_action(changeset, :create) do
      {:ok, _stat} ->
        _ = AnalyticsRepo.insert_all(UpdateStat, [changeset.changes], settings: [async_insert: 1])

        _ =
          Phoenix.Channel.Server.broadcast(
            NervesHub.PubSub,
            "deployment:#{deployment_group.id}:internal",
            "stat:logged",
            {:update_stat, update_bytes, saved_bytes}
          )

        :ok

      error ->
        error
    end
  end
end
