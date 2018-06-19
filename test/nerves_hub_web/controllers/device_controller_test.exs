defmodule NervesHubWeb.DeviceControllerTest do
  use NervesHubWeb.ConnCase.Browser

  alias NervesHub.Fixtures

  describe "index" do
    test "lists all devices", %{conn: conn} do
      conn = get(conn, device_path(conn, :index))
      assert html_response(conn, 200) =~ "Devices"
    end
  end

  describe "new device" do
    test "renders form with valid request params", %{conn: conn} do
      conn = get(conn, device_path(conn, :new))

      assert html_response(conn, 200) =~ "Create a Device"
    end
  end

  describe "create device" do
    test "redirects to show when data is valid", %{
      conn: conn,
      current_tenant: tenant,
      tenant_key: tenant_key
    } do
      firmware = Fixtures.firmware_fixture(tenant, tenant_key)

      device_params = %{
        # firmware_id: firmware.id,
        # tenant_id: tenant.id,
        architecture: firmware.architecture,
        platform: firmware.platform,
        identifier: "device_identifier",
        tags: "beta, beta-edge"
      }

      # check that we end up in the right place
      create_conn = post(conn, device_path(conn, :create), device: device_params)
      assert redirected_to(create_conn, 302) =~ device_path(conn, :index)

      # check that the proper creation side effects took place
      conn = get(conn, device_path(conn, :index))
      assert html_response(conn, 200) =~ device_params.identifier
    end
  end
end
