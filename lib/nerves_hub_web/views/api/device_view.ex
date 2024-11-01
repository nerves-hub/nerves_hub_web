defmodule NervesHubWeb.API.DeviceView do
  use NervesHubWeb, :api_view

  alias NervesHub.Devices
  alias NervesHub.Tracker

  def render("index.json", %{devices: devices, pagination: pagination}) do
    %{
      data: render_many(devices, __MODULE__, "device.json"),
      pagination: pagination
    }
  end

  def render("show.json", %{device: device}) do
    %{data: render_one(device, __MODULE__, "device.json")}
  end

  def render("device.json", %{device: device}) do
    %{
      identifier: device.identifier,
      tags: device.tags,
      version: version(device),
      online: Tracker.sync_online?(device),
      connection_status: device.connection_status,
      connection_established_at: device.connection_established_at,
      connection_disconnected_at: device.connection_disconnected_at,
      connection_last_seen_at: device.connection_last_seen_at,
      # deprecated
      last_communication: connection_last_seen_at(device),
      description: device.description,
      firmware_metadata: device.firmware_metadata,
      firmware_update_status: Devices.firmware_status(device),
      deployment: render_one(device.deployment, __MODULE__, "deployment.json", as: :deployment),
      updates_enabled: device.updates_enabled,
      updates_blocked_until: device.updates_blocked_until,
      org_name: device.org.name,
      product_name: device.product.name
    }
  end

  def render("deployment.json", %{deployment: deployment}) do
    %{
      firmware_uuid: deployment.firmware.uuid,
      firmware_version: deployment.firmware.version,
      is_active: deployment.is_active,
      name: deployment.name
    }
  end

  defp version(%{firmware_metadata: nil}), do: "unknown"
  defp version(%{firmware_metadata: %{version: vsn}}), do: vsn

  defp connection_last_seen_at(%{connection_last_seen_at: nil}), do: "never"
  defp connection_last_seen_at(%{connection_last_seen_at: dt}), do: to_string(dt)
end
