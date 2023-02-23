defmodule NervesHubWeb.API.FirmwareView do
  use NervesHubWeb, :api_view

  alias NervesHubWeb.API.FirmwareView

  def render("index.json", %{firmwares: firmwares}) do
    %{data: render_many(firmwares, FirmwareView, "firmware.json")}
  end

  def render("show.json", %{firmware: firmware}) do
    %{data: render_one(firmware, FirmwareView, "firmware.json")}
  end

  def render("firmware.json", %{firmware: %{product: %Ecto.Association.NotLoaded{}} = firmware}) do
    firmware = NervesHub.Repo.preload(firmware, :product)
    render("firmware.json", %{firmware: firmware})
  end

  def render("firmware.json", %{firmware: firmware}) do
    %{
      architecture: firmware.architecture,
      uuid: firmware.uuid,
      author: firmware.author,
      platform: firmware.platform,
      version: firmware.version,
      product: firmware.product.name
    }
  end
end
