defmodule NervesHubWeb.ArchiveControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Accounts.OrgUser
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

      assert redirected_to(conn) == "http://localhost:1234/uploads/archives/#{org.id}/#{product.id}/#{archive.uuid}.fw"
    end

    @tag :tmp_dir
    test "a view member can't download an archive", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      NervesHub.Repo.update_all(OrgUser, set: [role: :view])

      assert_error_sent(401, fn ->
        get(conn, ~p"/org/#{org}/#{product}/archives/#{archive}/download")
      end)
    end

    @tag :tmp_dir
    test "a custom role member can download an archive if the role grants it", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      give_custom_role(org, user, ["archive:download"])

      conn = get(conn, ~p"/org/#{org}/#{product}/archives/#{archive}/download")

      assert redirected_to(conn) == "http://localhost:1234/uploads/archives/#{org.id}/#{product.id}/#{archive.uuid}.fw"
    end

    @tag :tmp_dir
    test "a custom role member can't download an archive otherwise", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      give_custom_role(org, user, ["archive:upload"])

      assert_error_sent(401, fn ->
        get(conn, ~p"/org/#{org}/#{product}/archives/#{archive}/download")
      end)
    end

    test "404s for an archive that does not exist", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)

      assert_error_sent(404, fn ->
        get(conn, ~p"/org/#{org}/#{product}/archives/#{Ecto.UUID.generate()}/download")
      end)
    end
  end

  defp give_custom_role(org, user, permissions) do
    role = Fixtures.org_role_fixture(org, %{permissions: permissions})
    {:ok, org_user} = NervesHub.Accounts.get_org_user(org, user)
    {:ok, _} = NervesHub.Accounts.change_org_user_role(org_user, role)
  end
end
