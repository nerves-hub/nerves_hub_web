defmodule NervesHubWWWWeb.DeviceControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: false

  alias NervesHubWebCore.Devices
  alias NervesHubWWWWeb.DeviceLive

  describe "new device" do
    test "renders form with valid request params", %{conn: conn} do
      new_conn = get(conn, device_path(conn, :new))

      assert html_response(new_conn, 200) =~ "Create a Device"
    end
  end

  describe "create device" do
    test "redirects to show when data is valid", %{
      conn: conn
    } do
      device_params = %{
        identifier: "device_identifier",
        tags: "beta, beta-edge"
      }

      # check that we end up in the right place
      create_conn = post(conn, device_path(conn, :create), device: device_params)

      assert redirected_to(create_conn, 302) =~ device_path(conn, DeviceLive.Index)

      # check that the proper creation side effects took place
      conn = get(conn, device_path(conn, DeviceLive.Index))
      assert html_response(conn, 200) =~ device_params.identifier
    end
  end

  describe "delete device" do
    test "deletes chosen device", %{conn: conn, current_org: org} do
      [to_delete | _] = Devices.get_devices(org)
      conn = delete(conn, device_path(conn, :delete, to_delete))
      assert redirected_to(conn) == device_path(conn, DeviceLive.Index)

      conn = get(conn, device_path(conn, DeviceLive.Show, to_delete))
      assert html_response(conn, 302)
    end
  end
end
