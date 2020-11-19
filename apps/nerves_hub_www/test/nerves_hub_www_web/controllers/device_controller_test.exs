defmodule NervesHubWWWWeb.DeviceControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: false

  alias NervesHubWebCore.Devices
  alias NervesHubWebCore.Fixtures
  alias NervesHubDevice.Presence

  setup %{user: user, org: org} do
    [product: Fixtures.product_fixture(user, org)]
  end

  describe "new device" do
    test "renders form with valid request params", %{conn: conn, org: org, product: product} do
      new_conn = get(conn, Routes.device_path(conn, :new, org.name, product.name))

      assert html_response(new_conn, 200) =~ "Add Device"
    end
  end

  describe "create device" do
    test "redirects to show when data is valid", %{
      conn: conn,
      org: org,
      product: product
    } do
      device_params = %{
        identifier: "device_identifier",
        tags: "beta, beta-edge"
      }

      # check that we end up in the right place
      create_conn =
        post(conn, Routes.device_path(conn, :create, org.name, product.name),
          device: device_params
        )

      assert redirected_to(create_conn, 302) =~
               Routes.device_path(conn, :index, org.name, product.name)

      # check that the proper creation side effects took place
      conn = get(conn, Routes.device_path(conn, :index, org.name, product.name))
      assert html_response(conn, 200) =~ device_params.identifier
    end
  end

  describe "delete device" do
    test "deletes chosen device", %{conn: conn, org: org, product: product} do
      org_key = Fixtures.org_key_fixture(org)
      firmware = Fixtures.firmware_fixture(org_key, product)

      Fixtures.device_fixture(org, product, firmware)
      [to_delete | _] = Devices.get_devices_by_org_id_and_product_id(org.id, product.id)

      conn =
        delete(
          conn,
          Routes.device_path(conn, :delete, org.name, product.name, to_delete.identifier)
        )

      assert redirected_to(conn) == Routes.device_path(conn, :index, org.name, product.name)

      conn =
        get(conn, Routes.device_path(conn, :show, org.name, product.name, to_delete.identifier))

      assert html_response(conn, 404)
    end
  end

  describe "console" do
    test "shows information about device", %{conn: conn, org: org, product: product} do
      org_key = Fixtures.org_key_fixture(org)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      Presence.track(self(), "product:#{product.id}:devices", device.id, %{
        console_available: true,
        console_version: "0.9.0"
      })

      result =
        get(conn, Routes.device_path(conn, :console, org.name, product.name, device.identifier))

      assert html_response(result, 200) =~ device.identifier
    end
  end
end
