defmodule NervesHub.Workers.FirmwaresGC do
  use NervesHub.Worker,
    max_attempts: 5,
    queue: :garbage_collect_firmware,
    schedule: "*/15 * * * *"

  require Logger

  alias NervesHub.Firmwares

  @impl true
  def run(_job), do: run()

  def run() do
    Firmwares.get_firmware_by_expired_ttl()
    |> Enum.each(fn firmware ->
      case Firmwares.delete_firmware(firmware) do
        {:ok, _} ->
          Logger.debug("Garbage collected firmware #{firmware.uuid}")

        {:error, reason} ->
          Logger.error("Unable to garbage collect firmware #{inspect(reason)}")
      end
    end)
  end
end
