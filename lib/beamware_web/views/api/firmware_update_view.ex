defmodule BeamwareWeb.Api.FirmwareUpdateView do
  use BeamwareWeb, :api_view

  alias Beamware.Firmwares.Firmware

  def render("show.json", %{firmware: nil}) do
    %{"eligible_firmware_update" => nil}
  end
  def render("show.json", %{firmware: %Firmware{upload_metadata: %{"public_path" => url}}}) do
    %{"eligible_firmware_update" => url}
  end
end
