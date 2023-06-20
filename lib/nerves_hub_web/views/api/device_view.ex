defmodule NervesHubWeb.API.DeviceView do
  use NervesHubWeb, :api_view

  alias NervesHub.Tracker
  alias NervesHubWeb.API.DeviceView

  def render("index.json", %{devices: devices, pagination: pagination}) do
    %{
      data: render_many(devices, DeviceView, "device.json"),
      pagination: pagination
    }
  end

  def render("show.json", %{device: device}) do
    %{data: render_one(device, DeviceView, "device.json")}
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
      updates_enabled: device.updates_enabled
    }
  end

  defp version(%{firmware_metadata: nil}), do: "unknown"
  defp version(%{firmware_metadata: %{version: vsn}}), do: vsn

  defp last_communication(%{last_communication: nil}), do: "never"
  defp last_communication(%{last_communication: dt}), do: to_string(dt)
end
