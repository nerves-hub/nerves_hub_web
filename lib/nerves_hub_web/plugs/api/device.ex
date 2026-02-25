defmodule NervesHubWeb.API.Plugs.Device do
  import Plug.Conn

  alias NervesHub.Devices

  @preloads [:product, :latest_connection]

  def init(opts) do
    opts
  end

  def call(%{assigns: %{org: org}, params: %{"identifier" => identifier}} = conn, _opts) do
    device = Devices.get_device_by_identifier!(org, identifier, @preloads)

    assign(conn, :device, device)
  end

  def call(%{params: %{"identifier" => identifier}} = conn, _opts) do
    device = Devices.get_by_identifier!(identifier)

    assign(conn, :device, device)
  end
end
