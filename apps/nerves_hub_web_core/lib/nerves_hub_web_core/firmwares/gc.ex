defmodule NervesHubWebCore.Firmwares.GC do
  use GenServer

  require Logger

  alias NervesHubWebCore.Repo
  alias NervesHubWebCore.Firmwares

  @interval 30_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    interval = opts[:interval] || @interval
    Process.send_after(self(), :gc, interval)
    {:ok, interval}
  end

  def handle_info(:gc, interval) do
    Firmwares.get_firmware_by_expired_ttl()
    |> delete()

    Process.send_after(self(), :gc, interval)
    {:noreply, interval}
  end

  defp delete(firmwares) when is_list(firmwares) do
    firmwares
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
