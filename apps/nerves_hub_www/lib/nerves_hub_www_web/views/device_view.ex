defmodule NervesHubWWWWeb.DeviceView do
  use NervesHubWWWWeb, :view
  alias NervesHubDevice.Presence

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

  defdelegate device_status(device), to: Presence
end
