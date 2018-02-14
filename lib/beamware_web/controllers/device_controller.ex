defmodule BeamwareWeb.DeviceController do
  use BeamwareWeb, :controller

  alias Beamware.Devices

  def index(conn, _params) do
    conn
    |> render(
      "index.html",
      devices: Devices.get_devices(conn.assigns.tenant)
    )
  end
end
