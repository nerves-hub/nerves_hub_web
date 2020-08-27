defmodule NervesHubDeviceWeb.Plugs.DeviceTest do
  use DefaultMocks
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

    get_conn = get(conn, Routes.device_path(conn, :me))
    assert json_response(get_conn, 403)["status"] == "forbidden"
  end

  test "auth success with valid certs", %{cert: cert} do
    conn = NervesHubDeviceWeb.ConnCase.build_auth_conn(cert)

    plug_call_conn = Device.call(conn, [])
    # refute `sent` and `status` because the conn
    # should still be alive.
    refute plug_call_conn.state == :sent
    refute plug_call_conn.status == 403
    assert plug_call_conn.assigns[:device]

    get_conn = get(conn, Routes.device_path(conn, :me))
    assert json_response(get_conn, 200)
  end

  test "auth success updates last_communication", %{cert: cert} do
    conn = NervesHubDeviceWeb.ConnCase.build_auth_conn(cert)

    plug_call_conn = Device.call(conn, [])

    last_communication = plug_call_conn.assigns.device.last_communication

    # assert last_communication was updated
    assert Time.diff(DateTime.utc_now(), last_communication) < 2

    # refute `sent` and `status` because the conn
    # should still be alive.
    refute plug_call_conn.state == :sent
    refute plug_call_conn.status == 403
    assert plug_call_conn.assigns[:device]

    get_conn = get(conn, Routes.device_path(conn, :me))
    assert json_response(get_conn, 200)
  end

  test "firmware metadata updated when firmware headers are supplied", context do
    context.device
    |> Ecto.Changeset.change(%{firmware_metadata: nil})
    |> Repo.update()

    device = Repo.get(NervesHubWebCore.Devices.Device, context.device.id)
    firmware = Repo.preload(context.firmware, :product)

    assert is_nil(device.firmware_metadata)

    conn = NervesHubDeviceWeb.ConnCase.build_auth_conn(context.cert)

    plug_call_conn =
      conn
      |> Plug.Conn.put_req_header("x-nerveshub-uuid", firmware.uuid)
      |> Plug.Conn.put_req_header("x-nerveshub-product", firmware.product.name)
      |> Plug.Conn.put_req_header("x-nerveshub-version", firmware.version)
      |> Plug.Conn.put_req_header("x-nerveshub-architecture", firmware.architecture)
      |> Plug.Conn.put_req_header("x-nerveshub-platform", firmware.platform)
      |> Plug.Conn.put_req_header("x-nerveshub-author", firmware.author)
      |> Plug.Conn.put_req_header("x-nerveshub-description", firmware.description)
      |> Plug.Conn.put_req_header("x-nerveshub-vcs-identifier", firmware.vcs_identifier || "")
      |> Plug.Conn.put_req_header("x-nerveshub-misc", firmware.misc || "")
      |> Device.call([])

    assert %NervesHubWebCore.Devices.Device{} = plug_call_conn.assigns.device
    device = Repo.get(NervesHubWebCore.Devices.Device, context.device.id)
    assert firmware.uuid == device.firmware_metadata.uuid
    assert firmware.product.name == device.firmware_metadata.product
    assert firmware.version == device.firmware_metadata.version
    assert firmware.architecture == device.firmware_metadata.architecture
    assert firmware.platform == device.firmware_metadata.platform
    assert firmware.author == device.firmware_metadata.author
    assert firmware.description == device.firmware_metadata.description
    assert firmware.vcs_identifier == device.firmware_metadata.vcs_identifier
    assert firmware.misc == device.firmware_metadata.misc

    # refute `sent` and `status` because the conn
    # should still be alive.
    refute plug_call_conn.state == :sent
    refute plug_call_conn.status == 403
    device = plug_call_conn.assigns[:device]
    assert device

    get_conn = get(conn, Routes.device_path(conn, :me))
    assert json_response(get_conn, 200)
  end
end
