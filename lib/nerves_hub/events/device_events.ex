defmodule NervesHub.DeviceEvents do
  @moduledoc """
  Encapsulation of events to be sent to devices or the device channel
  """

  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Devices.UpdatePayload
  alias NervesHub.Firmwares
  alias NervesHub.Repo

  alias Phoenix.Channel.Server, as: ChannelServer

  def updated(device) do
    broadcast(device, "updated", %{})
  end

  def deployment_cleared(device) do
    broadcast(device, "deployment_updated", %{deployment_id: nil})
  end

  def deployment_assigned(device) do
    broadcast(device, "deployment_updated", %{deployment_id: device.deployment_id})
  end

  def moved_product(device) do
    :ok =
      ChannelServer.broadcast(NervesHub.PubSub, "device_socket:#{device.id}", "disconnect", %{})
  end

  def identify(device, user) do
    Repo.transact(fn ->
      DeviceTemplates.audit_request_action(user, device, "identify itself")

      broadcast(device, "identify", %{})

      {:ok, device}
    end)
  end

  def reboot(device, user) do
    Repo.transact(fn ->
      DeviceTemplates.audit_reboot(user, device)

      broadcast(device, "reboot", %{})

      {:ok, device}
    end)
  end

  def schedule_update(device, inflight_update, update_payload) do
    Repo.transact(fn ->
      inflight_update =
        inflight_update
        |> InflightUpdate.update_status_changeset("updating")
        |> Repo.update!()

      DeviceTemplates.audit_device_deployment_group_update_triggered(
        device,
        device.deployment_group
      )

      broadcast(device, "update", update_payload)

      :telemetry.execute([:nerves_hub, :devices, :update, :automatic], %{count: 1}, %{
        identifier: device.identifier,
        firmware_uuid: inflight_update.firmware_uuid
      })

      {:ok, inflight_update}
    end)
  end

  def manual_update(device, firmware, user, opts \\ []) do
    Repo.transact(fn ->
      url =
        if opts[:delta] do
          {:ok, url} = Devices.get_delta_or_firmware_url(device, firmware)
          url
        else
          {:ok, url} = Firmwares.get_firmware_url(firmware)
          url
        end

      {:ok, meta} = Firmwares.metadata_from_firmware(firmware)
      {:ok, device} = Devices.disable_updates(device, user)

      DeviceTemplates.audit_firmware_pushed(user, device, firmware)

      payload = %UpdatePayload{
        update_available: true,
        firmware_url: url,
        firmware_meta: meta
      }

      broadcast(device, "update", payload)

      :telemetry.execute([:nerves_hub, :devices, :update, :manual], %{count: 1})

      {:ok, device}
    end)
  end

  def topic(%Device{id: id}) do
    "device:#{id}"
  end

  defp broadcast(device, event, payload) do
    :ok = ChannelServer.broadcast(NervesHub.PubSub, topic(device), event, payload)
  end
end
