defmodule NervesHubWWWWeb.DeviceView do
  use NervesHubWWWWeb, :view

  alias NervesHubCore.Devices.Device
  alias NervesHubDeviceWeb.DeviceChannel

  def device_status(device) do
    cond do
      not DeviceChannel.online?(device) -> "offline"
      DeviceChannel.update_pending?(device) -> "update pending"
      DeviceChannel.online?(device) -> "online"
    end
  end

  def architecture_options do
    [
      "aarch64",
      "arm",
      "mipsel",
      "x86",
      "x86_atom",
      "x86_64"
    ]
  end

  def platform_options do
    [
      "bbb",
      "ev3",
      "qemu_arm",
      "rpi",
      "rpi0",
      "rpi2",
      "rpi3",
      "smartrent_hub",
      "x86_64"
    ]
  end
end
