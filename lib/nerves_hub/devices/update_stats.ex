defmodule NervesHub.Devices.UpdateStats do
  @moduledoc """
  Module for logging and querying device update statistics.
  """

  import Ecto.Query

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.UpdateStat
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareDelta
  alias NervesHub.Firmwares.FirmwareMetadata
  alias NervesHub.Helpers.Logging
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias Phoenix.Channel.Server, as: ChannelServer

  require Logger

  @spec stats_by_device(Device.t()) ::
          %{
            total_update_bytes: non_neg_integer(),
            total_saved_bytes: integer(),
            total_updates: non_neg_integer()
          }
  def stats_by_device(%Device{} = device) do
    UpdateStat
    |> where(device_id: ^device.id)
    |> select([s], %{
      total_update_bytes: sum(s.update_bytes),
      total_saved_bytes: sum(s.saved_bytes),
      total_updates: fragment("count(*)")
    })
    |> Repo.one()
    |> case do
      %{total_update_bytes: nil, total_saved_bytes: nil} ->
        %{total_update_bytes: 0, total_saved_bytes: 0, total_updates: 0}

      stats ->
        stats
    end
  end

  @spec stats_by_deployment(DeploymentGroup.t()) ::
          %{
            String.t() => %{
              total_update_bytes: non_neg_integer(),
              total_saved_bytes: integer(),
              total_updates: non_neg_integer(),
              target_firmware_uuid: String.t()
            }
          }
  def stats_by_deployment(deployment_group) do
    UpdateStat
    |> where(deployment_id: ^deployment_group.id)
    |> join(:inner, [s], f in Firmware,
      on:
        fragment("?::uuid", f.uuid) == s.target_firmware_uuid and
          f.product_id == ^deployment_group.product_id
    )
    |> group_by([s, f], [s.target_firmware_uuid, f.version])
    |> select([s, f], %{
      version: f.version,
      total_update_bytes: sum(s.update_bytes),
      total_saved_bytes: sum(s.saved_bytes),
      total_updates: fragment("count(*)"),
      target_firmware_uuid: s.target_firmware_uuid
    })
    |> Repo.all()
    |> Map.new(fn stat ->
      Map.pop(stat, :target_firmware_uuid)
    end)
  end

  @spec total_stats_by_product(Product.t()) ::
          %{
            total_update_bytes: non_neg_integer(),
            total_saved_bytes: integer(),
            total_updates: non_neg_integer()
          }
  def total_stats_by_product(product) do
    UpdateStat
    |> where(product_id: ^product.id)
    |> select([s], %{
      total_update_bytes: sum(s.update_bytes),
      total_saved_bytes: sum(s.saved_bytes),
      total_updates: fragment("count(*)")
    })
    |> Repo.one()
    |> case do
      %{total_update_bytes: nil, total_saved_bytes: nil} ->
        %{total_update_bytes: 0, total_saved_bytes: 0, total_updates: 0}

      stats ->
        stats
    end
  end

  @spec log_update(
          Device.t(),
          FirmwareMetadata.t() | nil
        ) :: :ok | {:error, Ecto.Changeset.t()}
  def log_update(device, nil) do
    log_stat(device)
  end

  def log_update(device, source_firmware_metadata) do
    case get_delta_from_metadata(
           device.product_id,
           source_firmware_metadata.uuid,
           device.firmware_metadata.uuid
         ) do
      %FirmwareDelta{} = delta ->
        log_stat(device, source_firmware_metadata, delta)

      _ ->
        log_stat(device, source_firmware_metadata)
    end
  end

  @spec log_stat(
          Device.t(),
          FirmwareMetadata.t() | nil,
          FirmwareDelta.t() | nil
        ) :: :ok | {:error, Ecto.Changeset.t()}
  defp log_stat(device, source_firmware_metadata \\ nil, delta \\ nil) do
    %{update_bytes: update_bytes, saved_bytes: saved_bytes} =
      get_byte_stats(delta, device.product_id, device.firmware_metadata.uuid)

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
            ChannelServer.broadcast(
              NervesHub.PubSub,
              "deployment:#{device.deployment_id}",
              "stat:logged",
              %{}
            )
          end

        :ok

      {:error, %Ecto.Changeset{} = changeset} = error ->
        Logging.log_message_to_sentry("Failed to create update stat for device", %{
          errors: changeset.errors,
          device_identifier: device.identifier
        })

        Logger.warning(
          "Could not create update stat for device",
          errors: changeset.errors,
          device_identifier: device.identifier,
          product_id: device.product_id
        )

        error
    end
  end

  @spec get_byte_stats(
          FirmwareDelta.t() | nil,
          product_id :: pos_integer(),
          target_firmware_uuid :: Ecto.UUID.t()
        ) ::
          %{
            update_bytes: integer(),
            saved_bytes: integer()
          }
  defp get_byte_stats(%FirmwareDelta{size: delta_size}, product_id, target_firmware_uuid) do
    {:ok, target_firmware} =
      Firmwares.get_firmware_by_product_id_and_uuid(product_id, target_firmware_uuid)

    %{update_bytes: delta_size, saved_bytes: target_firmware.size - delta_size}
  end

  defp get_byte_stats(nil, product_id, target_firmware_uuid) do
    case Firmwares.get_firmware_by_product_id_and_uuid(product_id, target_firmware_uuid) do
      {:ok, target_firmware} ->
        %{update_bytes: target_firmware.size, saved_bytes: 0}

      {:error, _} ->
        %{update_bytes: 0, saved_bytes: 0}
    end
  end

  @spec get_delta_from_metadata(
          product_id :: pos_integer(),
          source_uuid :: Ecto.UUID.t(),
          target_uuid :: Ecto.UUID.t()
        ) ::
          FirmwareDelta.t() | nil
  defp get_delta_from_metadata(product_id, source_uuid, target_uuid) do
    source_query =
      Firmware
      |> where([f], f.uuid == ^source_uuid)
      |> where([f], f.product_id == ^product_id)
      |> select([f], f.id)

    target_query =
      Firmware
      |> where([f], f.uuid == ^target_uuid)
      |> where([f], f.product_id == ^product_id)
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
