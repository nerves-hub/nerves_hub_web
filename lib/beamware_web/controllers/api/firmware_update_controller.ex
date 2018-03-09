defmodule BeamwareWeb.Api.FirmwareUpdateController do
  use BeamwareWeb, :controller

  alias Beamware.Firmwares
  alias Beamware.Firmwares.Firmware

  def show(%{assigns: %{device: device}} = conn, %{"version" => version, "architecture" => architecture, "platform" => platform}) do
    device
    |> Firmwares.get_eligible_firmware_update(%{
      version: version,
      architecture: architecture,
      platform: platform
    })
    |> case do
      {:ok, :none} ->
        conn
        |> render("show.json", %{firmware: nil})

      {:ok, %Firmware{} = firmware} ->
        conn
        |> render("show.json", %{firmware: firmware})
    end

  end
  def show(conn, _) do
    conn
    |> render("version_missing.html")
  end
end
