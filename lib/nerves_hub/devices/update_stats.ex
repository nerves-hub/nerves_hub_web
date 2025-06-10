defmodule NervesHub.Devices.UpdateStats do
  @moduledoc """
  Module for logging and queryingdevice update statistics.
  """

  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Devices.UpdateStat

  import Ecto.Query

  @spec stats_by_device(Device.t()) :: [map()]
  def stats_by_device(%Device{} = device) do
    AnalyticsRepo.all(
      from(s in UpdateStat,
        where: s.device_id == ^device.id,
        select: %{
          total_update_bytes: sum(s.update_bytes),
          total_saved_bytes: sum(s.saved_bytes),
          num_updates: count(s.id)
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
          num_updates: count(s.id)
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
          num_updates: count(s.id)
        }
      )
    )
  end

  @types [:fwup_full, :fwup_delta]
  @doc """
  Log an update statistic for a device.
  """
  @spec log_stat(
          Device.t(),
          DeploymentGroup.t(),
          type :: :fwup_full | :fwup_delta,
          update_bytes :: non_neg_integer(),
          saved_bytes :: integer()
        ) :: :ok | {:error, Ecto.Changeset.t()}
  def log_stat(
        %Device{} = device,
        %DeploymentGroup{} = deployment_group,
        type,
        update_bytes,
        saved_bytes \\ 0
      )
      when type in @types do
    source_uuid =
      case device do
        %{firmware_metadata: %{uuid: source_uuid}} -> source_uuid
        _ -> nil
      end

    changeset =
      UpdateStat.create_changeset(device, deployment_group, %{
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
