defmodule NervesHubWeb.API.FirmwareControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.Accounts
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Upload
  alias NervesHub.Fixtures
  alias NervesHub.Products
  alias NervesHub.Support.EspIdf
  alias NervesHub.Support.Fwup

  describe "index" do
    test "lists all firmwares", %{conn: conn, org: org, product: product} do
      path = Routes.api_firmware_path(conn, :index, org.name, product.name)
      conn = get(conn, path)
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "create firmware - error paths" do
    test "returns error when firmware file is invalid", %{conn: conn, org: org, product: product} do
      {boundary, body} = multipart_file("this is not a valid firmware file")
      path = Routes.api_firmware_path(conn, :create, org.name, product.name)

      conn =
        conn
        |> put_req_header("content-type", "multipart/form-data; boundary=#{boundary}")
        |> post(path, body)

      assert conn.status in [422, 500]
    end
  end

  describe "create firmware" do
    test "renders firmware when data is valid", %{
      conn: conn,
      user: user,
      org: org,
      product: product
    } do
      org_key = Fixtures.org_key_fixture(org, user)

      {:ok, signed_firmware_path} =
        Fwup.create_signed_firmware(org_key.name, "unsigned", "signed", %{product: product.name})

      {boundary, body} = multipart_file(File.read!(signed_firmware_path))
      path = Routes.api_firmware_path(conn, :create, org.name, product.name)

      conn =
        conn
        |> put_req_header("content-type", "multipart/form-data; boundary=#{boundary}")
        |> post(path, body)

      assert data = json_response(conn, 201)["data"]
      uuid = data["uuid"]
      assert data["tool"] == "fwup"

      conn = get(conn, Routes.api_firmware_path(conn, :show, org.name, product.name, uuid))
      assert json_response(conn, 200)["data"]["uuid"] == uuid
    end

    test "prevents too large of firmware", context do
      prev_size = Application.get_env(:nerves_hub, Upload)[:max_size]
      Application.put_env(:nerves_hub, Upload, max_size: 10)

      on_exit(fn ->
        Application.put_env(:nerves_hub, Upload, max_size: prev_size)
      end)

      {boundary, body} = multipart_file("non-sense fw data")

      path =
        Routes.api_firmware_path(context.conn, :create, context.org.name, context.product.name)

      assert_error_sent(:request_entity_too_large, fn ->
        context.conn
        |> put_req_header("content-type", "multipart/form-data; boundary=#{boundary}")
        |> post(path, body)
      end)
    end

    test "renders errors when data is invalid", %{conn: conn, org: org, product: product} do
      conn = post(conn, Routes.api_firmware_path(conn, :create, org.name, product.name))
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "create firmware addressed to the wrong product" do
    test "is rejected rather than filed under the declared product", %{
      conn: conn,
      user: user,
      org: org,
      product: product
    } do
      org_key = Fixtures.org_key_fixture(org, user)
      other_product = Fixtures.product_fixture(user, org)

      # Built for `other_product`, uploaded to `product`.
      {:ok, signed_firmware_path} =
        Fwup.create_signed_firmware(org_key.name, "unsigned", "signed", %{
          product: other_product.name
        })

      {boundary, body} = multipart_file(File.read!(signed_firmware_path))

      conn =
        conn
        |> put_req_header("content-type", "multipart/form-data; boundary=#{boundary}")
        |> post(Routes.api_firmware_path(conn, :create, org.name, product.name), body)

      assert response = json_response(conn, 422)
      assert response["errors"]["detail"] =~ other_product.name
      assert response["errors"]["detail"] =~ product.name

      # And nothing was stored anywhere.
      assert Firmwares.get_firmwares_by_product(other_product.id) == []
      assert Firmwares.get_firmwares_by_product(product.id) == []
    end

    test "an archive declaring the addressed product still uploads", %{
      conn: conn,
      user: user,
      org: org,
      product: product
    } do
      org_key = Fixtures.org_key_fixture(org, user)

      {:ok, signed_firmware_path} =
        Fwup.create_signed_firmware(org_key.name, "unsigned", "signed", %{product: product.name})

      {boundary, body} = multipart_file(File.read!(signed_firmware_path))

      conn =
        conn
        |> put_req_header("content-type", "multipart/form-data; boundary=#{boundary}")
        |> post(Routes.api_firmware_path(conn, :create, org.name, product.name), body)

      assert json_response(conn, 201)["data"]
    end
  end

  describe "create ESP-IDF firmware" do
    setup %{org: org, user: user, product: product} do
      # Products take only fwup until opted in, and ESP-IDF images must be
      # signed — so this needs both the setting and the matching public key.
      {:ok, product} = Products.update_product(product, %{allowed_update_tools: ["fwup", "esp-idf"]})

      {:ok, %{product: product, esp_key: Fixtures.esp_idf_key_fixture(org, user)}}
    end

    test "uploads an ESP-IDF application image", %{conn: conn, org: org, product: product} do
      {boundary, body} =
        multipart_file(EspIdf.signed_image(product: product.name, version: "1.4.2", chip_id: 0x0009))

      path = Routes.api_firmware_path(conn, :create, org.name, product.name)

      conn =
        conn
        |> put_req_header("content-type", "multipart/form-data; boundary=#{boundary}")
        |> post(path, body)

      assert data = json_response(conn, 201)["data"]
      assert data["version"] == "1.4.2"
      assert data["platform"] == "esp32s3"
      assert data["architecture"] == "xtensa"
      # Without this an API consumer cannot tell the two formats apart.
      assert data["tool"] == "esp-idf"

      conn = get(conn, Routes.api_firmware_path(conn, :show, org.name, product.name, data["uuid"]))
      assert json_response(conn, 200)["data"]["uuid"] == data["uuid"]
    end

    test "records the esp-idf tool and the key that signed it", %{
      conn: conn,
      org: org,
      product: product,
      esp_key: esp_key
    } do
      {boundary, body} = multipart_file(EspIdf.signed_image(product: product.name))

      conn =
        conn
        |> put_req_header("content-type", "multipart/form-data; boundary=#{boundary}")
        |> post(Routes.api_firmware_path(conn, :create, org.name, product.name), body)

      uuid = json_response(conn, 201)["data"]["uuid"]

      {:ok, firmware} = Firmwares.get_firmware_by_product_and_uuid(product, uuid)

      assert firmware.tool == "esp-idf"
      assert firmware.org_key_id == esp_key.id
      assert firmware.tool_metadata["idf_ver"] == "v5.2.1"
    end

    test "uploads with only an ESP-IDF key and no fwup key", %{conn: conn, org: org, product: product} do
      # An fwup upload into this org would fail with :no_public_keys — the two
      # schemes are filtered independently.
      assert Enum.all?(Accounts.list_org_keys(org.id), &(&1.scheme == :secure_boot_v2_rsa))

      {boundary, body} = multipart_file(EspIdf.signed_image(product: product.name))

      conn =
        conn
        |> put_req_header("content-type", "multipart/form-data; boundary=#{boundary}")
        |> post(Routes.api_firmware_path(conn, :create, org.name, product.name), body)

      assert json_response(conn, 201)["data"]
    end

    test "rejects a PROJECT_VER that is not a semantic version", %{conn: conn, org: org, product: product} do
      {boundary, body} = multipart_file(EspIdf.signed_image(product: product.name, version: "not-a-version"))

      conn =
        conn
        |> put_req_header("content-type", "multipart/form-data; boundary=#{boundary}")
        |> post(Routes.api_firmware_path(conn, :create, org.name, product.name), body)

      assert response = json_response(conn, 422)
      assert response["errors"]["detail"] =~ "not a valid semantic version"
      assert response["errors"]["detail"] =~ "PROJECT_VER"
    end

    test "rejects an unsigned ESP-IDF image", %{conn: conn, org: org, product: product} do
      {boundary, body} = multipart_file(EspIdf.image(product: product.name))

      conn =
        conn
        |> put_req_header("content-type", "multipart/form-data; boundary=#{boundary}")
        |> post(Routes.api_firmware_path(conn, :create, org.name, product.name), body)

      assert response = json_response(conn, 422)
      assert response["errors"]["detail"] =~ "signed"
    end

    test "rejects a file that is neither an fwup archive nor an ESP-IDF image", %{
      conn: conn,
      org: org,
      product: product
    } do
      {boundary, body} = multipart_file("this is not firmware at all")

      conn =
        conn
        |> put_req_header("content-type", "multipart/form-data; boundary=#{boundary}")
        |> post(Routes.api_firmware_path(conn, :create, org.name, product.name), body)

      assert response = json_response(conn, 422)
      assert response["errors"]["detail"] =~ "Unrecognised firmware format"
    end
  end

  describe "delete firmware" do
    setup [:create_firmware]

    test "deletes chosen firmware", %{conn: conn, org: org, product: product, firmware: firmware} do
      conn =
        delete(
          conn,
          Routes.api_firmware_path(conn, :delete, org.name, product.name, firmware.uuid)
        )

      assert response(conn, 204)

      conn =
        get(conn, Routes.api_firmware_path(conn, :show, org.name, product.name, firmware.uuid))

      assert response(conn, 404)
    end

    test "firmware delete with associated deployment", %{
      conn: conn,
      user: user,
      org: org,
      product: product,
      firmware: firmware
    } do
      Fixtures.deployment_group_fixture(firmware, %{user: user})

      conn =
        delete(
          conn,
          Routes.api_firmware_path(conn, :delete, org.name, product.name, firmware.uuid)
        )

      assert response(conn, 422)
    end
  end

  describe "download firmware" do
    setup [:create_firmware]

    test "downloads chosen firmware", %{conn: conn, org: org, product: product, firmware: firmware} do
      conn =
        get(
          conn,
          Routes.api_firmware_path(conn, :download, org.name, product.name, firmware.uuid)
        )

      assert redirected_to(conn) =~ "#{firmware.uuid}.fw"
    end

    test "user does not have required role to download chosen firmware", %{
      conn2: conn2,
      user2: user2,
      org: org,
      product: product,
      firmware: firmware
    } do
      Accounts.add_org_user(org, user2, %{role: :view})

      assert_error_sent(401, fn ->
        get(
          conn2,
          Routes.api_firmware_path(conn2, :download, org.name, product.name, firmware.uuid)
        )
      end)
      |> assert_authorization_error(401)
    end

    test "user does not belong to org of chosen firmware", %{
      conn2: conn2,
      org: org,
      product: product,
      firmware: firmware
    } do
      assert_error_sent(404, fn ->
        get(
          conn2,
          Routes.api_firmware_path(conn2, :download, org.name, product.name, firmware.uuid)
        )
      end)
      |> assert_authorization_error(404)
    end
  end

  defp create_firmware(%{user: user, org: org, product: product, tmp_dir: tmp_dir}) do
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    {:ok, %{firmware: firmware}}
  end

  defp multipart_file(data) do
    boundary = "----TestBoundary123"

    body = """
    --#{boundary}\r
    Content-Disposition: form-data; name="firmware"; filename="does_not_matter.txt"\r
    Content-Type: text/plain\r
    \r
    #{data}\r
    --#{boundary}--\r
    """

    {boundary, body}
  end
end
