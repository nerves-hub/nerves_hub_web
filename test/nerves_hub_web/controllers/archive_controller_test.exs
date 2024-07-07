defmodule NervesHubWeb.ArchiveControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures

  describe "download archive" do
    @tag :tmp_dir
    test "downloads chosen archive", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      conn = get(conn, ~p"/products/#{hashid(product)}/archives/#{archive.uuid}/download")

      assert redirected_to(conn) == "/uploads/archives/#{archive.uuid}.fw"
    end
  end
end
