defmodule NervesHubWWWWeb.Api.FirmwareUpdateController do
  use NervesHubWWWWeb, :controller

  alias NervesHubCore.Firmwares
  alias NervesHubCore.Firmwares.Firmware

  def show(%{assigns: %{device: device}} = conn, %{"version" => version}) do
    version
    |> Version.parse()
    |> case do
      {:ok, version} ->
        Firmwares.get_eligible_firmware_update(device, version)

      :error ->
        {:error, :invalid_version}
    end
    |> case do
      {:ok, :none} ->
        conn
        |> render("show.json", %{firmware: nil})

      {:ok, %Firmware{} = firmware} ->
        conn
        |> render("show.json", %{firmware: firmware})

      {:error, :invalid_version} ->
        conn
        |> render("error.json", %{
          error:
            "Invalid version supplied; ensure version is in Major.Minor.Patch format (e.g. 3.14.23 or 1.0.0)"
        })
    end
  end

  def show(conn, _) do
    conn
    |> render("error.json", %{error: "version is required"})
  end
end
