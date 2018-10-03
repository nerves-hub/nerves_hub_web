defmodule NervesHubDeviceWeb.Plugs.DeviceTest do
  use NervesHubDeviceWeb.ConnCase, async: true
  alias NervesHubDeviceWeb.Plugs.Device

  test "auth failure with invalid certs" do
    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.put_peer_data(%{})
      |> Plug.Conn.put_req_header("accept", "application/json")

    plug_call_conn = Device.call(conn, [])
    # assert state == sent and status == 403 to ensuer that
    # halt(conn) is called.
    assert plug_call_conn.state == :sent
    assert plug_call_conn.status == 403
    refute plug_call_conn.assigns[:device]

    get_conn = get(conn, device_path(conn, :me))
    assert json_response(get_conn, 403)["status"] == "forbidden"
  end

  test "auth success with valid certs" do
    conn = NervesHubDeviceWeb.ConnCase.build_auth_conn()

    plug_call_conn = Device.call(conn, [])
    # refute `sent` and `status` because the conn
    # should still be alive.
    refute plug_call_conn.state == :sent
    refute plug_call_conn.status == 403
    assert plug_call_conn.assigns[:device]

    get_conn = get(conn, device_path(conn, :me))
    assert json_response(get_conn, 200)
  end
end
