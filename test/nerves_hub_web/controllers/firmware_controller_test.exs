defmodule NervesHubWeb.FirmwareControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures

  describe "download firmware" do
    test "downloads chosen firmware", %{
      conn: conn,
      user: user,
      org: org
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)

      conn = get(conn, ~p"/products/#{hashid(product)}/firmware/#{firmware.uuid}/download")

      assert redirected_to(conn) == firmware.upload_metadata.public_path
    end
  end
end
