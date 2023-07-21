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
      online: Tracker.online?(device),
      last_communication: last_communication(device),
      description: device.description,
      firmware_metadata: device.firmware_metadata,
      firmware_update_status: Devices.firmware_status(device),
      updates_enabled: device.updates_enabled,
      updates_blocked_until: device.updates_blocked_until
    }
  end

  defp version(%{firmware_metadata: nil}), do: "unknown"
  defp version(%{firmware_metadata: %{version: vsn}}), do: vsn

  defp last_communication(%{last_communication: nil}), do: "never"
  defp last_communication(%{last_communication: dt}), do: to_string(dt)
end
