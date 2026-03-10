defmodule NervesHubWeb.API.Plugs.Device do
  import Plug.Conn

  alias NervesHub.Devices

  @preloads [:product, :latest_connection]

  def init(opts) do
    opts
  end

  def call(%{assigns: %{current_scope: %{org: org} = scope}, params: %{"identifier" => identifier}} = conn, _opts)
      when not is_nil(org) do
    device = Devices.get_by_identifier!(scope, identifier, @preloads)

    assign(conn, :device, device)
  end

  def call(%{assigns: %{current_scope: scope}, params: %{"identifier" => identifier}} = conn, _opts) do
    device = Devices.get_by_identifier!(scope, identifier, @preloads)

    assign(conn, :device, device)
  end
end
