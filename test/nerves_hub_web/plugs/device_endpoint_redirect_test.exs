defmodule NervesHubWeb.Plugs.DeviceEndpointRedirectTest do
  use NervesHubWeb.ConnCase.Browser, async: true
  use Plug.Test

  @endpoint NervesHubWeb.DeviceEndpoint

  test "redirect to docs.nerve-hub.org if the route isn't recognized" do
    conn = get(build_conn(), "/somewhere")

    assert Plug.Conn.get_resp_header(conn, "location") == ["https://docs.nerves-hub.org/"]
    assert conn.halted
  end
end
