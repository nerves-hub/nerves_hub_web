defmodule NervesHubWeb.Api.FirmwareUpdateView do
  use NervesHubWeb, :api_view

  alias NervesHubCore.Firmwares.Firmware

  def render("show.json", %{firmware: nil}) do
    %{"eligible_firmware_update" => nil}
  end

  def render("show.json", %{firmware: %Firmware{upload_metadata: %{"public_path" => url}}}) do
    %{"eligible_firmware_update" => url}
  end
end
