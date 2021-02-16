defmodule NervesHubDeviceWeb.DeviceView do
  use NervesHubDeviceWeb, :view
  alias NervesHubDeviceWeb.DeviceView
  alias NervesHubWebCore.Devices.UpdatePayload

  def render("show.json", %{device: device}) do
    %{data: render_one(device, DeviceView, "device.json")}
  end

  def render("device.json", %{device: device}) do
    %{
      identifier: device.identifier
    }
  end

  # We don't use the standard Phoenix render flow here because
  # this same payload gets dispatched via PubSub, which means it
  # already derives Jason.Encoder. This allows that implementation
  # to be the only source of where this payload gets serialized to JSON.
  def render("update.json", %{reply: %UpdatePayload{} = update_available}) do
    %{data: update_available}
  end
end
