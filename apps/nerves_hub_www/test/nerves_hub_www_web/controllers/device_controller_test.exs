defmodule NervesHubWWWWeb.DeviceControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: true

  alias NervesHubWebCore.Fixtures
  alias NervesHubWebCore.Devices

  describe "index" do
    test "lists all devices", %{conn: conn} do
      conn = get(conn, device_path(conn, :index))
      assert html_response(conn, 200) =~ "Devices"
    end

    test "devices default to offline", %{conn: conn} do
      conn = get(conn, device_path(conn, :index))
      refute html_response(conn, 200) =~ "online"
    end

    test "does not list devices for other orgs", %{conn: conn} do
      %{device: device} = Fixtures.smartrent_fixture()
      conn = get(conn, device_path(conn, :index))
      refute html_response(conn, 200) =~ device.identifier
    end
  end

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

      assert redirected_to(create_conn, 302) =~ device_path(conn, :index)

      # check that the proper creation side effects took place
      conn = get(conn, device_path(conn, :index))
      assert html_response(conn, 200) =~ device_params.identifier
    end
  end

  describe "edit device" do
    test "renders edit page", %{
      conn: conn,
      current_org: org
    } do
      [to_edit | _] = Devices.get_devices(org)

      conn =
        get(
          conn,
          device_path(conn, :edit, to_edit)
        )

      assert html_response(conn, 200) =~ "Device Details"
    end
  end

  describe "update device" do
    test "with valid params", %{
      conn: conn,
      current_org: org
    } do
      [to_update | _] = Devices.get_devices(org)

      device_params = %{
        identifier: "new_identifier",
        tags: "beta, beta-edge"
      }

      update_conn =
        put(
          conn,
          device_path(
            conn,
            :update,
            to_update.id
          ),
          device: device_params
        )

      assert redirected_to(update_conn) ==
               device_path(
                 conn,
                 :show,
                 to_update.id
               )

      show_conn =
        get(
          conn,
          device_path(conn, :show, to_update.id)
        )

      assert html_response(show_conn, 200) =~ "new_identifier"
    end
  end

  describe "delete device" do
    test "deletes chosen device", %{conn: conn, current_org: org} do
      [to_delete | _] = Devices.get_devices(org)
      conn = delete(conn, device_path(conn, :delete, to_delete))
      assert redirected_to(conn) == device_path(conn, :index)

      assert_error_sent(404, fn ->
        get(conn, device_path(conn, :show, to_delete))
      end)
    end
  end
end
