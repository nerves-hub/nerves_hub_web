defmodule NervesHubWeb.Live.ArchivesTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  alias NervesHub.Archives
  alias NervesHub.Fixtures
  alias NervesHub.Support
  alias NervesHub.Support.Fwup

  describe "index" do
    test "shows 'no archives' message", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives")
      |> assert_has("span", text: "#{product.name} doesn't have any available archives.")
    end

    test "lists all archives", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives")
      |> assert_has("h1", text: "Archives")
      |> assert_has("a", text: archive.uuid)
    end
  end

  describe "show" do
    test "shows the archive information", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives/#{archive.uuid}")
      |> assert_has("h1", text: archive.uuid)
    end

    test "delete archive", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org, %{name: "AmazingProduct"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives/#{archive.uuid}")
      |> assert_has("h1", text: archive.uuid)
      |> click_button("Delete")
      |> assert_path("/org/#{org.name}/#{product.name}/archives")
      |> assert_has("div", text: "Archive successfully deleted")
      |> assert_has("span", text: "#{product.name} doesn't have any available archives.")
    end
  end

  describe "sort and paginate" do
    test "sort by a new column", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      _archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives")
      |> assert_has("h1", text: "Archives")
      |> unwrap(fn view ->
        render_change(view, "sort", %{"sort" => "version"})
      end)
      |> assert_has("h1", text: "Archives")
    end

    test "sort by the same column toggles direction", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      _archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives?sort=inserted_at&sort_direction=asc")
      |> assert_has("h1", text: "Archives")
      |> unwrap(fn view ->
        render_change(view, "sort", %{"sort" => "inserted_at"})
      end)
      |> assert_has("h1", text: "Archives")
    end

    test "paginate to another page", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives?page_size=1")
      |> assert_has("a", text: archive.uuid)
      |> unwrap(fn view ->
        render_change(view, "paginate", %{"page" => "1"})
      end)
      |> assert_has("h1", text: "Archives")
    end

    test "change page size", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      _archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives")
      |> assert_has("h1", text: "Archives")
      |> unwrap(fn view ->
        render_change(view, "set-paginate-opts", %{"page-size" => "50"})
      end)
      |> assert_has("h1", text: "Archives")
    end
  end

  describe "delete archive from list" do
    test "deletes an archive from the index page", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org, %{name: "ArchiveProduct"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives")
      |> assert_has("a", text: archive.uuid)
      |> unwrap(fn view ->
        render_click(view, "delete-archive", %{"archive_uuid" => archive.uuid})
      end)
      |> assert_has("div", text: "Archive successfully deleted")
      |> refute_has("a", text: archive.uuid)
    end
  end

  describe "upload archive" do
    @tag :tmp_dir
    test "redirects after successful upload", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org, %{name: "CoolProduct"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      {:ok, signed_archive_path} =
        Support.Archives.create_signed_archive(org_key.name, "manifest", "signed-manifest", %{
          platform: "generic",
          architecture: "generic",
          version: "0.1.0",
          dir: tmp_dir
        })

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives")
      |> upload("Upload Archive", signed_archive_path)
      |> assert_path("/org/#{org.name}/#{product.name}/archives")
      |> assert_has("div", text: "Archive uploaded")
      |> assert_has("h1", text: "Archives")
    end

    test "error if corrupt firmware uploaded", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org, %{name: "CoolProduct"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      {:ok, signed_archive_path} =
        Support.Archives.create_signed_archive(org_key.name, "manifest", "signed-manifest", %{
          platform: "generic",
          architecture: "generic",
          version: "0.1.0",
          dir: tmp_dir
        })

      {:ok, corrupt_archive_path} = Fwup.corrupt_firmware_file(signed_archive_path, tmp_dir)

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives")
      |> upload("Upload Archive", corrupt_archive_path)
      |> assert_path("/org/#{org.name}/#{product.name}/archives")
      |> assert_has("div",
        text: "Archive corrupt, signature invalid, or the key used for signing hasn't been uploaded."
      )
    end

    @tag :tmp_dir
    test "error if org keys do not match firmware", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org, %{name: "CoolProduct"})

      Fwup.gen_key_pair("wrong", tmp_dir)

      {:ok, signed_archive_path} =
        Support.Archives.create_signed_archive("wrong", "manifest", "signed-manifest", %{
          platform: "generic",
          architecture: "generic",
          version: "0.1.0",
          dir: tmp_dir
        })

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives")
      |> upload("Upload Archive", signed_archive_path)
      |> assert_path("/org/#{org.name}/#{product.name}/archives")
      |> assert_has("div",
        text: "Archive corrupt, signature invalid, or the key used for signing hasn't been uploaded."
      )
    end
  end

  describe "archive-selected event" do
    test "is a noop", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      _archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives")
      |> unwrap(fn view ->
        render_click(view, "archive-selected", %{})
      end)
      |> assert_has("h1", text: "Archives")
    end
  end

  describe "delete error path (show page)" do
    test "shows error message when delete fails on show page", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org, %{name: "DeleteErrorShowProduct"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      stub(Archives, :delete_archive, fn _ ->
        {:error,
         %Ecto.Changeset{
           errors: [base: {"cannot delete", []}],
           data: %{},
           changes: %{},
           types: %{},
           valid?: false
         }}
      end)

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives/#{archive.uuid}")
      |> assert_has("h1", text: archive.uuid)
      |> click_button("Delete")
      |> assert_has("div", text: "The archive couldn't be deleted", exact: false)
    end
  end
end
