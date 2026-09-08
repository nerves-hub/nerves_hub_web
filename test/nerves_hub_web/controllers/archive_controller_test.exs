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

      conn = get(conn, ~p"/org/#{org}/#{product}/archives/#{archive}/download")

      assert redirected_to(conn) == "http://localhost:1234/uploads/archives/#{archive.uuid}.fw"
    end

    test "404s for an archive that does not exist", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)

      assert_error_sent(404, fn ->
        get(conn, ~p"/org/#{org}/#{product}/archives/#{Ecto.UUID.generate()}/download")
      end)
    end
  end
end
