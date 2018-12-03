defmodule NervesHubWWWWeb.Plugs.FetchFirmware do
  import Plug.Conn

  alias NervesHubWebCore.Firmwares

  def init(opts) do
    opts
  end

  def call(%{assigns: %{org: org, deployment: deployment}} = conn, _opts) do
    Firmwares.get_firmware(org, deployment.firmware_id)
    |> case do
      {:ok, firmware} ->
        conn
        |> assign(:firmware, firmware)

      _ ->
        conn
        |> halt()
    end
  end
end
