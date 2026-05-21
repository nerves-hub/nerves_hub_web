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
  alias NervesHub.ManagedDeployments
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

  def schedule_update(device_id, deployment_group, opts \\ []) do
    Logger.metadata(device_id: device_id)

    deployment_group =
      ManagedDeployments.load_current_release(deployment_group)
      |> Repo.preload([:org])

    priority_queue = Keyword.get(opts, :priority_queue, false)

    inflight_changeset =
      InflightUpdate.deployment_requested_changeset(deployment_group, device_id, priority_queue)

    Repo.transact(fn ->
      # we might need to do an upsert here
      {:ok, inflight_update} = Repo.insert(inflight_changeset)
      device = Devices.get_device(device_id)

      update_opts =
        if proxy_url = get_in(deployment_group.org.settings.firmware_proxy_url) do
          [firmware_proxy_url: proxy_url]
        else
          []
        end

      update_payload = Devices.resolve_update(device, deployment_group, update_opts)

      device = %{device | deployment_group: deployment_group}

      if opts[:user] do
        DeviceTemplates.audit_pushed_available_update(opts[:user], device_id, deployment_group)
      else
        DeviceTemplates.audit_device_deployment_group_update_triggered(
          device,
          device.deployment_group
        )
      end

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
          {:ok, url} = Devices.get_delta_url(device, firmware)
          url
        else
          {:ok, url} = Firmwares.get_firmware_url(firmware)
          url
        end

      firmware_url =
        if opts[:firmware_proxy_url] do
          opts[:firmware_proxy_url] <> "?firmware=#{Base.url_encode64(url, padding: false)}"
        else
          url
        end

      {:ok, _inflight_update} =
        InflightUpdate.manual_requested_changeset(device.id, firmware)
        |> Repo.insert()

      {:ok, meta} = Firmwares.metadata_from_firmware(firmware)
      {:ok, device} = Devices.disable_updates(device, user)

      DeviceTemplates.audit_firmware_pushed(user, device, firmware)

      payload = %UpdatePayload{
        update_available: true,
        firmware_url: firmware_url,
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
