defmodule NervesHub.DeviceEvents do
  @moduledoc """
  Encapsulation of events to be sent to devices or the device channel
  """

  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceMessages
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Devices.UpdatePayload
  alias NervesHub.Devices.Updates
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

      update_payload = Updates.resolve_update(device, deployment_group, update_opts)

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
      # When a delta is being sent it is the delta that the device downloads, so
      # it is the delta that describes the download.
      {:ok, firmware_or_delta} =
        if opts[:delta], do: Firmwares.get_delta(device, firmware), else: {:ok, firmware}

      {:ok, url} = Firmwares.get_firmware_url(firmware_or_delta)

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
      {:ok, device} = Updates.pause_automatic_updates(device, user)

      DeviceTemplates.audit_firmware_pushed(user, device, firmware)

      payload = %UpdatePayload{
        update_available: true,
        firmware_url: firmware_url,
        firmware_meta: meta,
        size: firmware_or_delta.size,
        checksum: firmware_or_delta.checksum,
        partials_checksums: firmware_or_delta.partials_checksums
      }

      :telemetry.execute([:nerves_hub, :devices, :update, :manual], %{count: 1})

      {:ok, {device, payload}}
    end)
    |> case do
      {:ok, {device, payload}} ->
        broadcast(device, "update", payload)
        {:ok, device}

      res ->
        res
    end
  end

  def topic(%Device{id: id}) do
    "device:#{id}"
  end

  defp broadcast(device, event, payload) do
    :ok = record_send(device, event, payload)
    :ok = ChannelServer.broadcast(NervesHub.PubSub, topic(device), event, payload)
  end

  # `NervesHubWeb.DeviceChannel` intercepts these two, so they stop at the
  # channel and are turned into other messages — the device never sees them,
  # and recording them here would claim a send that did not happen. Everything
  # else on this topic is fastlaned straight to the device's transport, which
  # means this broadcast is the only place it can be seen at all.
  defp record_send(_device, event, _payload) when event in ["updated", "deployment_updated"], do: :ok

  defp record_send(device, event, payload) do
    DeviceMessages.record(device, :sent, :device, event, payload)
  end
end
