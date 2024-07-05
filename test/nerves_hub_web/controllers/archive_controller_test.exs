defmodule NervesHubWeb.ArchiveControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Fixtures

  describe "download archive" do
    test "downloads chosen archive", %{
      conn: conn,
      user: user,
      org: org
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      archive = Fixtures.archive_fixture(org_key, product)

      conn = get(conn, ~p"/org/#{org.name}/#{product.name}/archives/#{archive.uuid}/download")

      assert redirected_to(conn) == "/uploads/archives/#{archive.uuid}.fw"
    end
  end
end
