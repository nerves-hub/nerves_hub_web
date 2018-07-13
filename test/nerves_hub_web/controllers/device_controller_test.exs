defmodule NervesHubWeb.DeviceControllerTest do
  use NervesHubWeb.ConnCase.Browser

  alias NervesHub.Fixtures
  alias NervesHub.Devices

  describe "index" do
    test "lists all devices", %{conn: conn} do
      conn = get(conn, device_path(conn, :index))
      assert html_response(conn, 200) =~ "Devices"
    end

    test "does not list devices for other tenants", %{conn: conn} do
      %{device: device} = Fixtures.smartrent_fixture()
      conn = get(conn, device_path(conn, :index))
      refute html_response(conn, 200) =~ device.identifier
    end
  end

  describe "new device" do
    test "renders form with valid request params", %{conn: conn} do
      product = Fixtures.product_fixture(conn)
      new_conn = get(conn, product_device_path(conn, :new, product.id))

      assert html_response(new_conn, 200) =~ "Create a Device"
      assert html_response(new_conn, 200) =~ "products/#{product.id}/devices"
    end

    test "does not render form with product id from wrong tenant", %{conn: conn} do
      %{product: product} = Fixtures.smartrent_fixture()

      new_conn = get(conn, product_device_path(conn, :new, product.id))

      assert redirected_to(new_conn, 302) =~ dashboard_path(new_conn, :index)
    end
  end

  describe "create device" do
    test "redirects to show when data is valid", %{
      conn: conn,
      current_tenant: tenant,
      tenant_key: tenant_key
    } do
      product = Fixtures.product_fixture(conn)
      firmware = Fixtures.firmware_fixture(tenant, tenant_key, product)

      device_params = %{
        architecture: firmware.architecture,
        platform: firmware.platform,
        identifier: "device_identifier",
        tags: "beta, beta-edge"
      }

      # check that we end up in the right place
      create_conn =
        post(conn, product_device_path(conn, :create, product.id), device: device_params)

      assert redirected_to(create_conn, 302) =~ device_path(conn, :index)

      # check that the proper creation side effects took place
      conn = get(conn, device_path(conn, :index))
      assert html_response(conn, 200) =~ device_params.identifier
    end

    test "cannot create device with product id from wrong tenant", %{
      conn: conn,
      current_tenant: tenant,
      tenant_key: tenant_key
    } do
      product = Fixtures.product_fixture(conn)
      firmware = Fixtures.firmware_fixture(tenant, tenant_key, product)

      %{product: wrong_product} = Fixtures.smartrent_fixture()

      device_params = %{
        architecture: firmware.architecture,
        platform: firmware.platform,
        identifier: "device_identifier",
        tags: "beta, beta-edge"
      }

      create_conn =
        post(conn, product_device_path(conn, :create, wrong_product.id), device: device_params)

      assert redirected_to(create_conn, 302) =~ dashboard_path(create_conn, :index)
    end
  end

  describe "edit device" do
    test "renders edit page", %{
      conn: conn,
      current_tenant: tenant
    } do
      [to_edit | _] = Devices.get_devices(tenant)
      conn = get(conn, product_device_path(conn, :edit, to_edit.product_id, to_edit))

      assert html_response(conn, 200) =~ "Device Details"
    end
  end

  describe "update device" do
    test "with valid params", %{
      conn: conn,
      current_tenant: tenant
    } do
      [to_update | _] = Devices.get_devices(tenant)

      device_params = %{
        identifier: "new_identifier",
        tags: "beta, beta-edge"
      }

      update_conn =
        put(
          conn,
          product_device_path(conn, :update, to_update.product_id, to_update.id),
          device: device_params
        )

      assert redirected_to(update_conn) ==
               product_device_path(conn, :show, to_update.product_id, to_update.id)

      show_conn = get(conn, product_device_path(conn, :show, to_update.product_id, to_update.id))
      assert html_response(show_conn, 200) =~ "new_identifier"
    end

    test "cannot update with product id from wrong tenant", %{
      conn: conn,
      current_tenant: tenant
    } do
      [to_update | _] = Devices.get_devices(tenant)
      %{product: wrong_product} = Fixtures.smartrent_fixture()

      device_params = %{
        identifier: "device_identifier",
        tags: "beta, beta-edge"
      }

      update_conn =
        put(
          conn,
          product_device_path(conn, :update, wrong_product.id, to_update.id),
          device: device_params
        )

      assert redirected_to(update_conn, 302) =~ dashboard_path(update_conn, :index)
    end
  end
end
