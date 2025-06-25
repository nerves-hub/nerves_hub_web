defmodule NervesHub.Devices.UpdateStats do
  @moduledoc """
  Module for logging and querying device update statistics.
  """

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.UpdateStat
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareDelta
  alias NervesHub.Firmwares.FirmwareMetadata
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias Phoenix.Channel.Server, as: ChannelServer

  import Ecto.Query

  require Logger

  @spec stats_by_device(Device.t()) ::
          %{
            total_update_bytes: non_neg_integer(),
            total_saved_bytes: integer(),
            num_updates: non_neg_integer()
          }
  def stats_by_device(%Device{} = device) do
    Repo.one(
      from(s in UpdateStat,
        where: s.device_id == ^device.id,
        select: %{
          total_update_bytes: sum(s.update_bytes),
          total_saved_bytes: sum(s.saved_bytes),
          num_updates: fragment("count(*)")
        }
      )
    )
    |> case do
      %{total_update_bytes: nil, total_saved_bytes: nil} ->
        %{total_update_bytes: 0, total_saved_bytes: 0, num_updates: 0}

      stats ->
        stats
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
    Repo.all(
      from(s in UpdateStat,
        where: s.deployment_id == ^deployment_group.id,
        # where: s.target_firmware_uuid == ^deployment_group.firmware.uuid,
        group_by: [s.target_firmware_uuid],
        select: %{
          total_update_bytes: sum(s.update_bytes),
          total_saved_bytes: sum(s.saved_bytes),
          num_updates: fragment("count(*)"),
          target_firmware_uuid: s.target_firmware_uuid
        }
      )
    )
    |> Enum.map(fn stat ->
      Map.pop(stat, :target_firmware_uuid)
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
    Repo.one(
      from(s in UpdateStat,
        where: s.product_id == ^product.id,
        select: %{
          total_update_bytes: sum(s.update_bytes),
          total_saved_bytes: sum(s.saved_bytes),
          num_updates: fragment("count(*)")
        }
      )
    )
    |> case do
      %{total_update_bytes: nil, total_saved_bytes: nil} ->
        %{total_update_bytes: 0, total_saved_bytes: 0, num_updates: 0}

      stats ->
        stats
    end
  end

  @spec log_update(
          Device.t(),
          FirmwareMetadata.t() | nil
        ) :: :ok | {:error, Ecto.Changeset.t()}
  def log_update(device, nil) do
    log_stat(device, nil, nil)
  end

  def log_update(device, source_firmware_metadata) do
    case get_delta_from_metadata(
           source_uuid: source_firmware_metadata.uuid,
           target_uuid: device.firmware_metadata.uuid
         ) do
      %FirmwareDelta{} = delta ->
        log_stat(device, source_firmware_metadata, delta)

      _ ->
        log_stat(device, source_firmware_metadata, nil)
    end
  end

  @spec log_stat(
          Device.t(),
          FirmwareMetadata.t() | nil,
          FirmwareDelta.t() | nil
        ) :: :ok | {:error, Ecto.Changeset.t()}
  defp log_stat(
         device,
         source_firmware_metadata,
         delta
       ) do
    %{update_bytes: update_bytes, saved_bytes: saved_bytes} =
      get_byte_stats(delta, device.firmware_metadata.uuid)

    source_firmware_uuid = get_in(source_firmware_metadata, [Access.key(:uuid)])
    deployment_id = get_deployment_id(device)

    UpdateStat.create_changeset(
      device,
      %{
        deployment_id: deployment_id,
        type: if(delta, do: "fwup_delta", else: "fwup_full"),
        source_firmware_uuid: source_firmware_uuid,
        target_firmware_uuid: device.firmware_metadata.uuid,
        update_bytes: update_bytes,
        saved_bytes: saved_bytes
      }
    )
    |> Repo.insert()
    |> case do
      {:ok, _stat} ->
        _ =
          if device.deployment_id do
            # IMPLEMENT ME IN THE UI HUMAN
            ChannelServer.broadcast(
              NervesHub.PubSub,
              "deployment:#{device.deployment_id}:internal",
              "stat:logged",
              {:update_stat, update_bytes, saved_bytes}
            )
          end

        :ok

      {:error, %Ecto.Changeset{} = changeset} = error ->
        Logger.warning(
          "Could not create update stat for device",
          errors: changeset.errors,
          device_identifier: device.identifier,
          product_id: device.product_id
        )

        error
    end
  end

  @spec get_byte_stats(FirmwareDelta.t() | nil, Ecto.UUID.t()) :: %{
          update_bytes: integer(),
          saved_bytes: integer()
        }
  defp get_byte_stats(%FirmwareDelta{size: delta_size}, target_firmware_uuid) do
    target_firmware = Firmwares.get_firmware_by_uuid(target_firmware_uuid)

    %{update_bytes: delta_size, saved_bytes: target_firmware.size - delta_size}
  end

  defp get_byte_stats(nil, target_firmware_uuid) do
    case Firmwares.get_firmware_by_uuid(target_firmware_uuid) do
      %Firmware{} = target_firmware ->
        %{update_bytes: target_firmware.size, saved_bytes: 0}

      nil ->
        %{update_bytes: 0, saved_bytes: 0}
    end
  end

  @spec get_delta_from_metadata(source_uuid: Ecto.UUID.t(), target_uuid: Ecto.UUID.t()) ::
          FirmwareDelta.t() | nil
  defp get_delta_from_metadata(source_uuid: source_uuid, target_uuid: target_uuid) do
    source_query =
      Firmware
      |> where([f], f.uuid == ^source_uuid)
      |> select([f], f.id)

    target_query =
      Firmware
      |> where([f], f.uuid == ^target_uuid)
      |> select([f], f.id)

    FirmwareDelta
    |> where([fd], source_id: subquery(source_query))
    |> where([fd], target_id: subquery(target_query))
    |> where([fd], fd.status == :completed)
    |> Repo.one()
  end

  defp get_deployment_id(%{deployment_id: nil}), do: nil

  defp get_deployment_id(device) do
    device = Repo.preload(device, deployment_group: :firmware)

    case device.deployment_group.firmware.uuid == device.firmware_metadata.uuid do
      true -> device.deployment_id
      false -> nil
    end
  end
end
