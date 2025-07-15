defmodule NervesHubWeb.API.FirmwareControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.Fixtures
  alias NervesHub.Support.Fwup

  describe "index" do
    test "lists all firmwares", %{conn: conn, org: org, product: product} do
      path = Routes.api_firmware_path(conn, :index, org.name, product.name)
      conn = get(conn, path)
      assert json_response(conn, 200)["data"] == []
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

      conn = get(conn, Routes.api_firmware_path(conn, :show, org.name, product.name, uuid))
      assert json_response(conn, 200)["data"]["uuid"] == uuid
    end

    test "prevents too large of firmware", context do
      prev_size = Application.get_env(:nerves_hub, NervesHub.Firmwares.Upload)[:max_size]
      Application.put_env(:nerves_hub, NervesHub.Firmwares.Upload, max_size: 10)

      on_exit(fn ->
        Application.put_env(:nerves_hub, NervesHub.Firmwares.Upload, max_size: prev_size)
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
      org: org,
      product: product,
      firmware: firmware
    } do
      Fixtures.deployment_group_fixture(org, firmware)

      conn =
        delete(
          conn,
          Routes.api_firmware_path(conn, :delete, org.name, product.name, firmware.uuid)
        )

      assert response(conn, 409)
    end
  end

  defp create_firmware(%{user: user, org: org, product: product}) do
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
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
