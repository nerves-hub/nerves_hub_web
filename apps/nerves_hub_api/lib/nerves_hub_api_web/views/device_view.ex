defmodule NervesHubAPIWeb.DeviceView do
  use NervesHubAPIWeb, :view
  alias NervesHubAPIWeb.DeviceView
  alias NervesHubDevice.Presence

  defdelegate device_status(device), to: Presence

  def render("index.json", %{devices: devices}) do
    %{data: render_many(devices, DeviceView, "device.json")}
  end

  def render("show.json", %{device: device}) do
    %{data: render_one(device, DeviceView, "device.json")}
  end

  def render("device.json", %{device: device}) do
    %{
      identifier: device.identifier,
      tags: device.tags,
      status: device_status(device)
    }
  end
end
