defmodule BeamwareWeb.DeviceView do
  use BeamwareWeb, :view

  alias Beamware.Devices.Device

  def last_communication(%Device{last_communication: nil}), do: ""

  def last_communication(%Device{last_communication: l}),
    do: Timex.format!(l, "{YYYY}-{0M}-{D} {h24}:{m}:{s}")
end
