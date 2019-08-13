defmodule NervesHubWebCore.Firmwares.GC do
  require Logger

  alias NervesHubWebCore.Firmwares

  def run() do
    Logger.debug("FIRMWARE GC STARTED")
    
    Firmwares.get_firmware_by_expired_ttl()
    |> Enum.each(fn firmware ->
      case Firmwares.delete_firmware(firmware) do
        :ok ->
          Logger.debug("Garbage collected firmware #{firmware.uuid}")

        {:error, reason} ->
          Logger.error("Unable to garbage collect firmware #{inspect(reason)}")
      end
    end)
  end
end
