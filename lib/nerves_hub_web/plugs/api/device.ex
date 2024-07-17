defmodule NervesHubWeb.API.Plugs.Device do
  import Plug.Conn

  alias NervesHub.Devices

  def init(opts) do
    opts
  end

  def call(%{params: %{"identifier" => identifier}} = conn, _opts) do
    device = Devices.get_device_by_identifier!(conn.assigns.org, identifier)

    assign(conn, :device, device)
  end
end
