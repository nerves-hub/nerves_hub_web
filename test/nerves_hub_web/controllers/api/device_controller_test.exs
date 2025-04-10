defmodule NervesHubWeb.API.DeviceControllerTest do
  use NervesHubWeb.APIConnCase, async: false
  use Mimic

  import Phoenix.ChannelTest

  alias NervesHub.Devices
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  describe "create devices" do
    test "renders device when data is valid", %{conn: conn, org: org, product: product} do
      identifier = "api-device-1234"

      device = %{
        identifier: identifier,
        description: "test device",
        tags: ["test"],
        updates_enabled: true
      }

      conn = post(conn, Routes.api_device_path(conn, :create, org.name, product.name), device)
      assert json_response(conn, 201)["data"]

      conn =
        get(conn, Routes.api_device_path(conn, :show, org.name, product.name, device.identifier))

      assert json_response(conn, 200)["data"]["identifier"] == identifier
      assert json_response(conn, 200)["data"]["updates_enabled"] == true
    end

    test "renders errors when data is invalid", %{conn: conn, org: org} do
      conn = post(conn, Routes.api_key_path(conn, :create, org.name))
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "index" do
    test "lists all devices for an org", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)

      device = Fixtures.device_fixture(org, product, firmware)

      conn = get(conn, Routes.api_device_path(conn, :index, org.name, product.name))

      assert json_response(conn, 200)["data"]

      assert Enum.find(conn.assigns.devices, fn %{identifier: identifier} ->
               device.identifier == identifier
             end)
    end
  end

  describe "show" do
    test "device that the user has access to, using nested url", %{
      conn: conn,
      user: user,
      org: org
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)

      device = Fixtures.device_fixture(org, product, firmware)

      conn =
        get(conn, Routes.api_device_path(conn, :show, org.name, product.name, device.identifier))

      assert json_response(conn, 200)["data"]

      assert json_response(conn, 200)["data"]["identifier"] == device.identifier
    end

    test "device that the user does not have access to, using nested url", %{
      conn: conn,
      user: user,
      org: org
    } do
      product = Fixtures.product_fixture(user, org)

      assert_error_sent(404, fn ->
        get(conn, Routes.api_device_path(conn, :show, org.name, product.name, "abcd"))
      end)
      |> assert_authorization_error(404)
    end

    test "device that the user has access to, using short url", %{
      conn: conn,
      user: user,
      org: org
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)

      device = Fixtures.device_fixture(org, product, firmware)

      conn =
        get(conn, Routes.api_device_path(conn, :show, device.identifier))

      assert json_response(conn, 200)["data"]

      assert json_response(conn, 200)["data"]["identifier"] == device.identifier
    end

    test "device that the user does not have access to, using short url", %{conn: conn} do
      assert_error_sent(404, fn ->
        get(conn, Routes.api_device_path(conn, :show, "abcd"))
      end)
      |> assert_authorization_error(404)
    end
  end

  describe "delete devices" do
    test "deletes chosen device", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)

      to_delete = Fixtures.device_fixture(org, product, firmware)

      # fully load all the associations
      to_delete = Devices.get_complete_device(to_delete.id)

      conn =
        delete(
          conn,
          Routes.api_device_path(conn, :delete, org.name, product.name, to_delete.identifier)
        )

      assert response(conn, 204)

      assert_error_sent(404, fn ->
        get(
          conn,
          Routes.api_device_path(conn, :show, org.name, product.name, to_delete.identifier)
        )
      end)
      |> assert_authorization_error(404)
    end
  end

  describe "update devices" do
    test "updates chosen device", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)

      Fixtures.device_fixture(org, product, firmware)

      [to_update | _] = Devices.get_devices_by_org_id_and_product_id(org.id, product.id)

      conn =
        put(
          conn,
          Routes.api_device_path(conn, :update, org.name, product.name, to_update.identifier),
          %{
            tags: ["a", "b", "c", "d"]
          }
        )

      assert json_response(conn, 201)["data"]

      conn =
        get(
          conn,
          Routes.api_device_path(conn, :show, org.name, product.name, to_update.identifier)
        )

      assert json_response(conn, 200)
      assert conn.assigns.device.tags == ["a", "b", "c", "d"]
    end
  end

  describe "authenticate devices" do
    test "valid certificate", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)

      device = Fixtures.device_fixture(org, product, firmware)
      %{cert: ca, key: ca_key} = Fixtures.ca_certificate_fixture(org)

      cert =
        X509.PrivateKey.new_ec(:secp256r1)
        |> X509.PublicKey.derive()
        |> X509.Certificate.new("CN=#{device.identifier}", ca, ca_key)

      _device_certificate = Fixtures.device_certificate_fixture(device, cert)

      cert64 =
        cert
        |> X509.Certificate.to_pem()
        |> Base.encode64()

      conn =
        post(conn, Routes.api_device_path(conn, :auth, org.name, product.name), %{
          "certificate" => cert64
        })

      assert json_response(conn, 200)["data"]
    end
  end

  describe "upgrade firmware" do
    test "pushing new firmware to a device", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware_one = Fixtures.firmware_fixture(org_key, product)
      firmware_two = Fixtures.firmware_fixture(org_key, product)

      device = Fixtures.device_fixture(org, product, firmware_one)

      Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device.id}")

      url = Routes.api_device_path(conn, :upgrade, org.name, product.name, device.identifier)
      conn = post(conn, url, %{"uuid" => firmware_two.uuid})

      assert response(conn, 204)
      assert_broadcast("deployments/update", %{})
    end
  end

  describe "clear penalty box" do
    test "success, with nested url", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      {:ok, device} = Devices.update_device(device, %{updates_blocked_until: DateTime.utc_now()})

      conn =
        delete(
          conn,
          Routes.api_device_path(conn, :penalty, org.name, product.name, device.identifier)
        )

      assert response(conn, 204)

      assert device.updates_blocked_until
      device = Repo.reload(device)
      refute device.updates_blocked_until
    end

    test "auth failure, with nested url", %{conn2: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      {:ok, device} = Devices.update_device(device, %{updates_blocked_until: DateTime.utc_now()})

      assert_error_sent(404, fn ->
        delete(
          conn,
          Routes.api_device_path(conn, :penalty, org.name, product.name, device.identifier)
        )
      end)
      |> assert_authorization_error(404)
    end

    test "success, with short url", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      {:ok, device} = Devices.update_device(device, %{updates_blocked_until: DateTime.utc_now()})

      conn =
        delete(
          conn,
          Routes.api_device_path(conn, :penalty, device.identifier)
        )

      assert response(conn, 204)

      assert device.updates_blocked_until
      device = Repo.reload(device)
      refute device.updates_blocked_until
    end

    test "auth failure, with short url", %{conn2: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      {:ok, device} = Devices.update_device(device, %{updates_blocked_until: DateTime.utc_now()})

      assert_error_sent(401, fn ->
        delete(
          conn,
          Routes.api_device_path(conn, :penalty, device.identifier)
        )
      end)
      |> assert_authorization_error(401)
    end
  end

  describe "reboot" do
    test "success, with nested url", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      conn =
        post(
          conn,
          Routes.api_device_path(conn, :reboot, org.name, product.name, device.identifier)
        )

      assert response(conn, 200)
    end

    test "auth failure, with nested url", %{conn2: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      assert_error_sent(404, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :reboot, org.name, product.name, device.identifier)
        )
      end)
      |> assert_authorization_error(404)
    end

    test "success, with short url", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      conn = post(conn, Routes.api_device_path(conn, :reboot, device.identifier))

      assert response(conn, 200)
    end

    test "auth failure, with short url", %{conn2: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      assert_error_sent(401, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :reconnect, device.identifier)
        )
      end)
      |> assert_authorization_error(401)
    end
  end

  describe "reconnect" do
    test "success, with nested url", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      conn =
        post(
          conn,
          Routes.api_device_path(conn, :reconnect, org.name, product.name, device.identifier)
        )

      assert response(conn, 200)
    end

    test "auth failure, with nested url", %{conn2: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      assert_error_sent(404, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :reconnect, org.name, product.name, device.identifier)
        )
      end)
      |> assert_authorization_error(404)
    end

    test "success, with short url", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      conn = post(conn, Routes.api_device_path(conn, :reconnect, device.identifier))

      assert response(conn, 200)
    end

    test "auth failure, with short url", %{conn2: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      assert_error_sent(401, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :reconnect, device.identifier)
        )
      end)
      |> assert_authorization_error(401)
    end
  end

  describe "code" do
    test "success, with nested url", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      conn =
        post(
          conn,
          Routes.api_device_path(conn, :code, org.name, product.name, device.identifier),
          %{body: "boop"}
        )

      assert response(conn, 200)
    end

    test "auth failure, with nested url", %{conn2: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      assert_error_sent(404, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :code, org.name, product.name, device.identifier),
          %{body: "boop"}
        )
      end)
      |> assert_authorization_error(404)
    end

    test "success, with short url", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      conn = post(conn, Routes.api_device_path(conn, :code, device.identifier), %{body: "boop"})

      assert response(conn, 200)
    end

    test "auth failure, with short url", %{conn2: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      assert_error_sent(401, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :code, device.identifier),
          %{body: "boop"}
        )
      end)
      |> assert_authorization_error(401)
    end
  end

  describe "upgrade" do
    test "success, with nested url", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      conn =
        post(
          conn,
          Routes.api_device_path(conn, :upgrade, org.name, product.name, device.identifier),
          %{uuid: firmware.uuid}
        )

      assert response(conn, 204)
    end

    test "auth failure, with nested url", %{conn2: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      assert_error_sent(404, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :upgrade, org.name, product.name, device.identifier),
          %{uuid: firmware.uuid}
        )
      end)
      |> assert_authorization_error(404)
    end

    test "success, with short url", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      conn =
        post(conn, Routes.api_device_path(conn, :upgrade, device.identifier), %{
          uuid: firmware.uuid
        })

      assert response(conn, 204)
    end

    test "auth failure, with short url", %{conn2: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      assert_error_sent(401, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :upgrade, device.identifier),
          %{uuid: firmware.uuid}
        )
      end)
      |> assert_authorization_error(401)
    end
  end

  describe "move device to a new product" do
    test "success, with nested url", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      org2 = Fixtures.org_fixture(user, %{name: "org2"})
      product2 = Fixtures.product_fixture(user, org2, %{name: "product2"})

      {:ok, device} = Devices.update_device(device, %{updates_blocked_until: DateTime.utc_now()})

      conn =
        post(
          conn,
          Routes.api_device_path(conn, :move, org.name, product.name, device.identifier),
          %{
            "new_org_name" => org2.name,
            "new_product_name" => product2.name
          }
        )

      assert response(conn, 200)

      device = Repo.reload(device)
      assert device.org_id == org2.id
      assert device.product_id == product2.id
    end

    test "auth failure, with nested url", %{conn2: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      org2 = Fixtures.org_fixture(user, %{name: "org2"})
      product2 = Fixtures.product_fixture(user, org2, %{name: "product2"})

      {:ok, device} = Devices.update_device(device, %{updates_blocked_until: DateTime.utc_now()})

      assert_error_sent(404, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :move, org.name, product.name, device.identifier),
          %{
            "new_org_name" => org2.name,
            "new_product_name" => product2.name
          }
        )
      end)
      |> assert_authorization_error(404)

      device = Repo.reload(device)
      assert device.org_id == org.id
      assert device.product_id == product.id
    end

    test "failure: missing permissions in new product, with nested url
      ",
         %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      user2 = Fixtures.user_fixture()
      org2 = Fixtures.org_fixture(user2, %{name: "org2"})
      product2 = Fixtures.product_fixture(user2, org2, %{name: "product2"})

      {:ok, device} = Devices.update_device(device, %{updates_blocked_until: DateTime.utc_now()})

      assert_error_sent(401, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :move, org.name, product.name, device.identifier),
          %{
            "new_org_name" => org2.name,
            "new_product_name" => product2.name
          }
        )
      end)
      |> assert_authorization_error()
    end

    test "success, with short url", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      org2 = Fixtures.org_fixture(user, %{name: "org2"})
      product2 = Fixtures.product_fixture(user, org2, %{name: "product2"})

      {:ok, device} = Devices.update_device(device, %{updates_blocked_until: DateTime.utc_now()})

      conn =
        post(
          conn,
          Routes.api_device_path(conn, :move, device.identifier),
          %{
            "new_org_name" => org2.name,
            "new_product_name" => product2.name
          }
        )

      assert response(conn, 200)

      device = Repo.reload(device)
      assert device.org_id == org2.id
      assert device.product_id == product2.id
    end

    test "auth failure, with short url", %{conn2: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      org2 = Fixtures.org_fixture(user, %{name: "org2"})
      product2 = Fixtures.product_fixture(user, org2, %{name: "product2"})

      {:ok, device} = Devices.update_device(device, %{updates_blocked_until: DateTime.utc_now()})

      assert_error_sent(401, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :move, device.identifier),
          %{
            "new_org_name" => org2.name,
            "new_product_name" => product2.name
          }
        )
      end)
      |> assert_authorization_error(401)

      device = Repo.reload(device)
      assert device.org_id == org.id
      assert device.product_id == product.id
    end

    test "failure: missing permissions in new product, with short url
      ",
         %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      user2 = Fixtures.user_fixture()
      org2 = Fixtures.org_fixture(user2, %{name: "org2"})
      product2 = Fixtures.product_fixture(user2, org2, %{name: "product2"})

      {:ok, device} = Devices.update_device(device, %{updates_blocked_until: DateTime.utc_now()})

      assert_error_sent(401, fn ->
        post(
          conn,
          Routes.api_device_path(conn, :move, device.identifier),
          %{
            "new_org_name" => org2.name,
            "new_product_name" => product2.name
          }
        )
      end)
      |> assert_authorization_error()
    end
  end

  describe "scripts: list" do
    test "success, with nested url", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      path =
        Routes.api_device_script_path(conn, :index, org.name, product.name, device.identifier)

      conn
      |> get(path)
      |> json_response(200)
      |> assert
    end

    test "auth failure, with nested url", %{conn2: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      assert_error_sent(404, fn ->
        get(
          conn,
          Routes.api_device_script_path(conn, :index, org.name, product.name, device.identifier)
        )
      end)
      |> assert_authorization_error(404)
    end

    test "success, with short url", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      path = Routes.api_script_path(conn, :index, device.identifier)

      conn
      |> get(path)
      |> json_response(200)
      |> assert
    end

    test "auth failure, with short url", %{conn2: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      assert_error_sent(401, fn ->
        get(
          conn,
          Routes.api_script_path(conn, :index, device.identifier)
        )
      end)
      |> assert_authorization_error(401)
    end
  end

  describe "scripts: send" do
    test "success, with nested url", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)
      script = Fixtures.support_script_fixture(product, user)

      path =
        Routes.api_device_script_path(
          conn,
          :send,
          org.name,
          product.name,
          device.identifier,
          script.id
        )

      NervesHub.Scripts.Runner
      |> expect(:send, fn _, _ -> {:ok, "hello"} end)

      conn
      |> post(path)
      |> response(200)
      |> assert
    end

    test "auth failure, with nested url", %{conn2: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)
      script = Fixtures.support_script_fixture(product, user)

      assert_error_sent(404, fn ->
        post(
          conn,
          Routes.api_device_script_path(
            conn,
            :send,
            org.name,
            product.name,
            device.identifier,
            script.id
          )
        )
      end)
      |> assert_authorization_error(404)
    end

    test "success, with short url", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)
      script = Fixtures.support_script_fixture(product, user)

      path =
        Routes.api_script_path(
          conn,
          :send,
          device.identifier,
          script.id
        )

      NervesHub.Scripts.Runner
      |> expect(:send, fn _, _ -> {:ok, "hello"} end)

      conn
      |> post(path)
      |> response(200)
      |> assert
    end

    test "auth failure, with short url", %{conn2: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)
      script = Fixtures.support_script_fixture(product, user)

      assert_error_sent(401, fn ->
        post(
          conn,
          Routes.api_script_path(
            conn,
            :send,
            device.identifier,
            script.id
          )
        )
      end)
      |> assert_authorization_error(401)
    end
  end
end
