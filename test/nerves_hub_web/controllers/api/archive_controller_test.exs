defmodule NervesHubWeb.API.ArchiveControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.Accounts
  alias NervesHub.Archives
  alias NervesHub.Fixtures
  alias NervesHub.Support

  @moduletag :tmp_dir

  @invalid_signature "The signature does not match any of this organization's signing keys, or the file is corrupt."

  describe "index" do
    test "lists no archives", %{conn: conn, org: org, product: product} do
      conn = get(conn, Routes.api_archive_path(conn, :index, org.name, product.name))
      assert json_response(conn, 200)["data"] == []
    end

    test "lists a product's archives", %{conn: conn, org: org, product: product} = context do
      %{archive: archive} = create_archive(context)

      conn = get(conn, Routes.api_archive_path(conn, :index, org.name, product.name))

      assert [data] = json_response(conn, 200)["data"]
      assert data["uuid"] == archive.uuid
      assert data["version"] == archive.version
      assert data["platform"] == archive.platform
      assert data["architecture"] == archive.architecture
      assert data["size"] == archive.size
      assert data["inserted_at"]
    end
  end

  describe "show" do
    test "shows an archive", %{conn: conn, org: org, product: product} = context do
      %{archive: archive} = create_archive(context)

      conn = get(conn, Routes.api_archive_path(conn, :show, org.name, product.name, archive.uuid))

      assert json_response(conn, 200)["data"]["uuid"] == archive.uuid
    end

    test "is not found for another product's archive",
         %{conn: conn, user: user, org: org, product: product} = context do
      %{archive: archive} = create_archive(context)
      other_product = Fixtures.product_fixture(user, org)

      conn = get(conn, Routes.api_archive_path(conn, :show, org.name, other_product.name, archive.uuid))

      assert json_response(conn, 404)
      assert {:ok, _} = Archives.get(product, archive.uuid)
    end
  end

  describe "create" do
    test "uploads a signed archive", %{conn: conn, user: user, org: org, product: product, tmp_dir: tmp_dir} do
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      path = Fixtures.archive_file_fixture(org_key, product, %{dir: tmp_dir, version: "1.2.0+build.5"})

      conn = post_archive(conn, org, product, File.read!(path))

      assert data = json_response(conn, 201)["data"]
      assert data["version"] == "1.2.0+build.5"
      assert {:ok, archive} = Archives.get(product, data["uuid"])
      assert archive.org_key_id == org_key.id
    end

    test "rejects an archive signed by a key the org doesn't have", %{
      conn: conn,
      user: user,
      org: org,
      product: product,
      tmp_dir: tmp_dir
    } do
      Fixtures.org_key_fixture(org, user, tmp_dir)
      Support.Fwup.gen_key_pair("stranger", tmp_dir)

      {:ok, path} =
        Support.Archives.create_signed_archive("stranger", "unsigned", "signed", %{dir: tmp_dir, product: product.name})

      conn = post_archive(conn, org, product, File.read!(path))

      assert json_response(conn, 422)["errors"]["detail"] == @invalid_signature
    end

    test "rejects an archive when the org has no signing keys", %{
      conn: conn,
      user: user,
      org: org,
      product: product,
      tmp_dir: tmp_dir
    } do
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      path = Fixtures.archive_file_fixture(org_key, product, %{dir: tmp_dir})
      {:ok, _} = Accounts.delete_org_key(org_key)

      conn = post_archive(conn, org, product, File.read!(path))

      assert json_response(conn, 422)["errors"]["detail"] ==
               "This organization has no signing keys. Register one before uploading."
    end

    test "rejects an archive whose metadata is incomplete", %{
      conn: conn,
      user: user,
      org: org,
      product: product,
      tmp_dir: tmp_dir
    } do
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      Support.Fwup.create_firmware_with_invalid_metadata(tmp_dir, "unsigned")
      {:ok, path} = Support.Fwup.sign_firmware(tmp_dir, org_key.name, "unsigned", "signed")

      conn = post_archive(conn, org, product, File.read!(path))

      assert json_response(conn, 422)["errors"]["detail"] =~ "must include meta-product"
    end

    test "accepts uploads larger than the default request limit",
         %{conn: conn, user: user, org: org, product: product} =
           context do
      Fixtures.org_key_fixture(org, user, context.tmp_dir)

      conn = post_archive(conn, org, product, :binary.copy("x", 2_000_000))

      assert json_response(conn, 422)["errors"]["detail"] == @invalid_signature
    end

    test "rejects a version that is not SemVer", %{conn: conn, user: user, org: org, product: product, tmp_dir: tmp_dir} do
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      path = Fixtures.archive_file_fixture(org_key, product, %{dir: tmp_dir, version: "release-1.2"})

      conn = post_archive(conn, org, product, File.read!(path))

      assert json_response(conn, 422)["errors"]["version"]
    end

    test "user does not have required role to upload", %{
      conn2: conn2,
      user2: user2,
      org: org,
      product: product
    } do
      Accounts.add_org_user(org, user2, %{role: :view})

      assert_error_sent(401, fn ->
        post_archive(conn2, org, product, "not an archive")
      end)
      |> assert_authorization_error(401)
    end
  end

  describe "download" do
    test "redirects to the archive", %{conn: conn, org: org, product: product} = context do
      %{archive: archive} = create_archive(context)

      conn = get(conn, Routes.api_archive_path(conn, :download, org.name, product.name, archive.uuid))

      assert redirected_to(conn) =~ "archives/#{archive.uuid}.fw"
    end

    test "user does not have required role to download",
         %{conn2: conn2, user2: user2, org: org, product: product} =
           context do
      %{archive: archive} = create_archive(context)
      Accounts.add_org_user(org, user2, %{role: :view})

      assert_error_sent(401, fn ->
        get(conn2, Routes.api_archive_path(conn2, :download, org.name, product.name, archive.uuid))
      end)
      |> assert_authorization_error(401)
    end

    test "user does not belong to the archive's org", %{conn2: conn2, org: org, product: product} = context do
      %{archive: archive} = create_archive(context)

      assert_error_sent(404, fn ->
        get(conn2, Routes.api_archive_path(conn2, :download, org.name, product.name, archive.uuid))
      end)
      |> assert_authorization_error(404)
    end
  end

  defp create_archive(%{user: user, org: org, product: product, tmp_dir: tmp_dir}) do
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    %{archive: Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})}
  end

  defp post_archive(conn, org, product, data) do
    boundary = "----TestBoundary123"

    body = """
    --#{boundary}\r
    Content-Disposition: form-data; name="archive"; filename="does_not_matter.fw"\r
    Content-Type: application/octet-stream\r
    \r
    #{data}\r
    --#{boundary}--\r
    """

    conn
    |> put_req_header("content-type", "multipart/form-data; boundary=#{boundary}")
    |> post(Routes.api_archive_path(conn, :create, org.name, product.name), body)
  end
end
