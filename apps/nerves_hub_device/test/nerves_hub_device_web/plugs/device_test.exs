defmodule NervesHubDeviceWeb.Plugs.DeviceTest do
  use NervesHubDeviceWeb.ConnCase, async: false
  alias NervesHubDeviceWeb.Plugs.Device
  alias NervesHubWebCore.Repo

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

  test "last known firmware updated when firmware header supplied", context do
    context.device
    |> Ecto.Changeset.change(%{last_known_firmware_id: nil})
    |> Repo.update()

    fetch_device_fw_id = fn ->
      Repo.get(NervesHubWebCore.Devices.Device, context.device.id).last_known_firmware_id
    end

    assert is_nil(fetch_device_fw_id.())

    conn = NervesHubDeviceWeb.ConnCase.build_auth_conn()

    plug_call_conn =
      conn
      |> Plug.Conn.put_req_header("x-nerveshub-uuid", context.firmware.uuid)
      |> Device.call([])

    assert %NervesHubWebCore.Devices.Device{} = plug_call_conn.assigns.device
    assert context.firmware.id == fetch_device_fw_id.()

    # refute `sent` and `status` because the conn
    # should still be alive.
    refute plug_call_conn.state == :sent
    refute plug_call_conn.status == 403
    device = plug_call_conn.assigns[:device]
    assert device

    get_conn = get(conn, device_path(conn, :me))
    assert json_response(get_conn, 200)
  end
end
