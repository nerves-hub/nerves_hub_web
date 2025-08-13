defmodule NervesHub.Devices.UpdateStats do
  @moduledoc """
  Module for logging and querying device update statistics.
  """

  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.UpdateStat
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareDelta
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Products.Product

  import Ecto.Query

  def enabled? do
    Application.get_env(:nerves_hub, :analytics_enabled)
  end

  @types [:fwup_full, :fwup_delta]

  @spec stats_by_device(Device.t()) ::
          %{
            total_update_bytes: non_neg_integer(),
            total_saved_bytes: integer(),
            num_updates: non_neg_integer()
          }
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
    |> case do
      [] -> %{total_update_bytes: 0, total_saved_bytes: 0, num_updates: 0}
      [stats] -> stats
    end
  end

  @spec stats_by_deployment(DeploymentGroup.t()) ::
          %{
            String.t() => %{
              total_update_bytes: non_neg_integer(),
              total_saved_bytes: integer(),
              num_updates: non_neg_integer(),
              source_firmware_uuid: String.t()
            }
          }
  def stats_by_deployment(deployment_group) do
    AnalyticsRepo.all(
      from(s in UpdateStat,
        where: s.deployment_id == ^deployment_group.id,
        where: s.target_firmware_uuid == ^deployment_group.firmware.uuid,
        group_by: [s.source_firmware_uuid],
        select: %{
          total_update_bytes: sum(s.update_bytes),
          total_saved_bytes: sum(s.saved_bytes),
          num_updates: fragment("count()"),
          source_firmware_uuid: s.source_firmware_uuid
        }
      )
    )
    |> Enum.map(fn stat ->
      Map.pop(stat, :source_firmware_uuid)
    end)
    |> Map.new()
  end

  @spec total_stats_by_product(Product.t()) ::
          %{
            total_update_bytes: non_neg_integer(),
            total_saved_bytes: integer(),
            num_updates: non_neg_integer()
          }
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
    |> case do
      [] -> %{total_update_bytes: 0, total_saved_bytes: 0, num_updates: 0}
      [stats] -> stats
    end
  end

  @spec log_full_update(
          Device.t(),
          DeploymentGroup.t() | nil,
          Firmware.t()
        ) :: :ok | {:error, Ecto.Changeset.t()}
  def log_full_update(
        %Device{} = device,
        deployment_group,
        %Firmware{} = target
      ) do
    log_stat(device, deployment_group, target, :fwup_full, target.size, 0)
  end

  @spec log_delta_update(
          Device.t(),
          DeploymentGroup.t() | nil,
          Firmware.t(),
          FirmwareDelta.t()
        ) :: :ok | {:error, Ecto.Changeset.t()}
  def log_delta_update(
        %Device{} = device,
        deployment_group,
        %Firmware{} = target,
        %FirmwareDelta{} = firmware_delta
      ) do
    target_size = target.size

    delta_size =
      if firmware_delta.size > 0 do
        firmware_delta.size
      else
        target_size
      end

    saved = target_size - delta_size
    log_stat(device, deployment_group, target, :fwup_delta, delta_size, saved)
  end

  defp log_stat(
         %Device{} = device,
         deployment_group,
         %Firmware{} = target,
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
      UpdateStat.create_changeset(
        device,
        deployment_group,
        %{
          timestamp: DateTime.utc_now(),
          type: Atom.to_string(type),
          source_firmware_uuid: source_uuid,
          target_firmware_uuid: target.uuid,
          update_bytes: update_bytes,
          saved_bytes: saved_bytes
        }
      )

    case Ecto.Changeset.apply_action(changeset, :create) do
      {:ok, _stat} ->
        _ = AnalyticsRepo.insert_all(UpdateStat, [changeset.changes], settings: [async_insert: 1])

        _ =
          if deployment_group do
            Phoenix.Channel.Server.broadcast(
              NervesHub.PubSub,
              "deployment:#{deployment_group.id}:internal",
              "stat:logged",
              {:update_stat, update_bytes, saved_bytes}
            )
          end

        :ok

      {:error, %Ecto.Changeset{}} = error ->
        error
    end
  end
end
