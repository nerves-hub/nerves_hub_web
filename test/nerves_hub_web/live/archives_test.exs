defmodule NervesHubWeb.Live.ArchivesTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures
  alias NervesHub.Support
  alias NervesHub.Support.Fwup

  describe "index" do
    test "shows 'no archives yet' message", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)

      conn
      |> visit("/products/#{hashid(product)}/archives")
      |> assert_has("h3", text: "#{product.name} doesn’t have any archives yet")
    end

    test "lists all archives", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/products/#{hashid(product)}/archives")
      |> assert_has("h1", text: "Archives")
      |> assert_has("a", text: archive.uuid)
    end

    test "delete archive from list", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/products/#{hashid(product)}/archives")
      |> assert_has("h1", text: "Archives")
      |> assert_has("a", text: archive.uuid)
      |> click_link("Delete")
      |> assert_has("div", text: "Archive successfully deleted")
      |> assert_has("h3", text: "#{product.name} doesn’t have any archives yet")
    end
  end

  describe "show" do
    test "shows the archive information", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/products/#{hashid(product)}/archives/#{archive.uuid}")
      |> assert_has("h1", text: "Archive #{archive.version}")
    end

    test "delete archive", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org, %{name: "AmazingProduct"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/products/#{hashid(product)}/archives/#{archive.uuid}")
      |> assert_has("h1", text: "Archive #{archive.version}")
      |> click_link("Delete")
      |> assert_path("/products/#{hashid(product)}/archives")
      |> assert_has("div", text: "Archive successfully deleted")
      |> assert_has("h3", text: "#{product.name} doesn’t have any archives yet")
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
      |> visit("/products/#{hashid(product)}/archives/upload")
      |> assert_has("h1", text: "Add Archive")
      |> unwrap(fn view ->
        file_input(view, "form", :archive, [
          %{
            name: "signed.fw",
            content: File.read!(signed_archive_path)
          }
        ])
        |> render_upload("signed.fw")

        render(view)
      end)
      |> assert_path("/products/#{hashid(product)}/archives")
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
      |> visit("/products/#{hashid(product)}/archives/upload")
      |> assert_has("h1", text: "Add Archive")
      |> unwrap(fn view ->
        file_input(view, "form", :archive, [
          %{
            name: "signed.fw",
            content: File.read!(corrupt_archive_path)
          }
        ])
        |> render_upload("signed.fw")

        render(view)
      end)
      |> assert_path("/products/#{hashid(product)}/archives/upload")
      |> assert_has("div", text: "Archive corrupt, signature invalid, or missing public key")
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
      |> visit("/products/#{hashid(product)}/archives/upload")
      |> assert_has("h1", text: "Add Archive")
      |> unwrap(fn view ->
        file_input(view, "form", :archive, [
          %{
            name: "signed.fw",
            content: File.read!(signed_archive_path)
          }
        ])
        |> render_upload("signed.fw")

        render(view)
      end)
      |> assert_path("/products/#{hashid(product)}/archives/upload")
      |> assert_has("div", text: "Archive corrupt, signature invalid, or missing public key")
    end
  end
end
