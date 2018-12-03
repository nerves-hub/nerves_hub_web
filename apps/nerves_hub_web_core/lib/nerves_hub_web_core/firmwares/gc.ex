defmodule NervesHubWebCore.Firmwares.GC do
  require Logger

  alias NervesHubWebCore.Repo
  alias NervesHubWebCore.Firmwares

  def run() do
    Firmwares.get_firmware_by_expired_ttl()
    |> Enum.each(fn firmware ->
      case Repo.delete(firmware) do
        {:ok, _firmware} ->
          Logger.debug("Garbage collected firmware #{firmware.uuid}")

        {:error, reason} ->
          Logger.error("Unable to garbage collect firmware #{inspect(reason)}")
      end
    end)
  end
end
