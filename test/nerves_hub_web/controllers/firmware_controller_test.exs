defmodule NervesHubWeb.FirmwareControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures

  describe "download firmware" do
    test "downloads chosen firmware", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn = get(conn, ~p"/org/#{org}/#{product}/firmware/#{firmware}/download")

      assert redirected_to(conn) == firmware.upload_metadata.public_path
    end

    test "404s for firmware that does not exist", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)

      assert_error_sent(404, fn ->
        get(conn, ~p"/org/#{org}/#{product}/firmware/#{Ecto.UUID.generate()}/download")
      end)
    end
  end
end
