defmodule NervesHubAPIWeb.DeviceControllerTest do
  use NervesHubAPIWeb.ConnCase

  describe "create devices" do
    test "renders device when data is valid", %{conn: conn, org: org} do
      identifier = "api-device-1234"
      device = %{identifier: identifier, description: "test device", tags: ["test"]}

      conn = post(conn, device_path(conn, :create, org.name), device)
      assert json_response(conn, 201)["data"]

      conn = get(conn, device_path(conn, :show, org.name, device.identifier))
      assert json_response(conn, 200)["data"]["identifier"] == identifier
    end

    test "renders errors when data is invalid", %{conn: conn, org: org} do
      conn = post(conn, key_path(conn, :create, org.name))
      assert json_response(conn, 422)["errors"] != %{}
    end
  end
end
