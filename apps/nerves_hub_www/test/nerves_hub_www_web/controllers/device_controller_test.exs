defmodule NervesHubWWWWeb.DeviceControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: false

  alias NervesHubWebCore.Devices
  alias NervesHubWWWWeb.DeviceLive
  alias NervesHubWebCore.Fixtures

  setup %{current_user: user, current_org: org} do
    [product: Fixtures.product_fixture(user, org)]
  end

  describe "new device" do
    test "renders form with valid request params", %{conn: conn, product: product} do
      new_conn = get(conn, product_device_path(conn, :new, product.id))

      assert html_response(new_conn, 200) =~ "Create a Device"
    end
  end

  describe "create device" do
    test "redirects to show when data is valid", %{
      conn: conn,
      product: product
    } do
      device_params = %{
        identifier: "device_identifier",
        tags: "beta, beta-edge"
      }

      # check that we end up in the right place
      create_conn =
        post(conn, product_device_path(conn, :create, product.id), device: device_params)

      assert redirected_to(create_conn, 302) =~ product_device_path(conn, :index, product.id)

      # check that the proper creation side effects took place
      conn = get(conn, product_device_path(conn, :index, product.id))
      assert html_response(conn, 200) =~ device_params.identifier
    end
  end

  describe "delete device" do
    test "deletes chosen device", %{conn: conn, current_org: org, product: product} do
      org_key = Fixtures.org_key_fixture(org)
      firmware = Fixtures.firmware_fixture(org_key, product)

      Fixtures.device_fixture(org, product, firmware)
      [to_delete | _] = Devices.get_devices_by_org_id_and_product_id(org.id, product.id)
      conn = delete(conn, product_device_path(conn, :delete, product.id, to_delete))
      assert redirected_to(conn) == product_device_path(conn, :index, product.id)

      conn = get(conn, product_device_path(conn, DeviceLive.Show, product.id, to_delete))
      assert html_response(conn, 302)
    end
  end
end
