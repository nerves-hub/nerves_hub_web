defmodule NervesHubWeb.API.FirmwareJSON do
  @moduledoc false

  def index(%{firmwares: firmwares}) do
    %{data: for(firmware <- firmwares, do: firmware(firmware))}
  end

  def show(%{firmware: firmware}) do
    %{data: firmware(firmware)}
  end

  defp firmware(firmware) do
    %{
      architecture: firmware.architecture,
      author: firmware.author,
      platform: firmware.platform,
      product: firmware.product.name,
      uuid: firmware.uuid,
      version: firmware.version
    }
  end
end
