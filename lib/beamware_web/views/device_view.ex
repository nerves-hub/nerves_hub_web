defmodule BeamwareWeb.DeviceView do
  use BeamwareWeb, :view

  alias Beamware.Devices.Device

  def last_communication(%Device{last_communication: nil}), do: ""

  def last_communication(%Device{last_communication: l}),
    do: Timex.format!(l, "{YYYY}-{0M}-{D} {h24}:{m}:{s}")

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
