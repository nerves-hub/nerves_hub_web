defmodule NervesHubWeb.Plugs.FetchFirmware do
  import Plug.Conn

  alias NervesHub.Firmwares

  def init(opts) do
    opts
  end

  def call(%{assigns: %{tenant: tenant, deployment: deployment}} = conn, _opts) do
    Firmwares.get_firmware(tenant, deployment.firmware_id)
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
