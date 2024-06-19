defmodule NervesHubWeb.ArchiveControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Fixtures
  alias NervesHub.Support

  setup %{user: user, org: org} do
    [product: Fixtures.product_fixture(user, org)]
  end

  describe "new archive" do
    test "renders form with valid request params", %{conn: conn, org: org, product: product} do
      new_conn = get(conn, Routes.archive_path(conn, :new, org.name, product.name))

      assert html_response(new_conn, 200) =~ "Upload Archive"
    end
  end

  describe "create archive" do
    test "redirects to show when data is valid", %{conn: conn, user: user, org: org, product: product} do
      org_key = Fixtures.org_key_fixture(org, user)

      {:ok, file_path} =
        Support.Archives.create_signed_archive(org_key.name, "manifest", "signed-manifest", %{
          platform: "generic",
          architecture: "generic",
          version: "0.1.0"
        })

      upload = %Plug.Upload{
        path: file_path,
        filename: Path.basename(file_path)
      }

      create_conn =
        post(conn, Routes.archive_path(conn, :create, org.name, product.name),
          archive: %{file: upload}
        )

      assert redirected_to(create_conn, 302)
    end
  end

  describe "delete archive" do
    test "deletes chosen archive", %{conn: conn, user: user, org: org, product: product} do
      org_key = Fixtures.org_key_fixture(org, user)
      archive = Fixtures.archive_fixture(org_key, product)

      conn =
        delete(
          conn,
          Routes.archive_path(conn, :delete, org.name, product.name, archive.uuid)
        )

      assert redirected_to(conn) == Routes.archive_path(conn, :index, org.name, product.name)
    end
  end
end
