defmodule NervesHubDeviceWeb.DeviceView do
  use NervesHubDeviceWeb, :view
  alias NervesHubDeviceWeb.DeviceView

  def render("show.json", %{device: device}) do
    %{data: render_one(device, DeviceView, "device.json")}
  end

  def render("device.json", %{device: device}) do
    %{
      identifier: device.identifier
    }
  end

  def render("update.json", %{reply: reply}) do
    %{data: reply}
  end
end
