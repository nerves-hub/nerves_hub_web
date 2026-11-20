defmodule NervesHubWeb.Live.ArchivesTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Archives
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.Support
  alias NervesHub.Support.Fwup

  describe "index" do
    test "explains archives to a product with none", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives")
      |> assert_has("#archives-empty h2", text: "Ship files that aren’t firmware")
      |> assert_has("#archives-empty label", text: "Choose a file")
      |> refute_has("#archive-tabs")
    end

    test "lists archives with who delivers them", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      %{product: product, delivered: delivered, idle: idle} = with_a_release(user, org, tmp_dir)

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives")
      |> assert_has("h1", text: "Archives")
      |> assert_has("#archive-tabs a", text: "Delivered")
      |> assert_has("#archive-#{delivered.uuid}", text: "Calibration tables")
      |> assert_has("#archive-#{delivered.uuid}", text: "Fleet")
      |> assert_has("#archive-#{delivered.uuid}", text: "with 1.0.0")
      |> assert_has("#archive-#{idle.uuid}", text: "Not in a current release")
    end

    test "the tabs split delivered from not delivered", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      %{product: product, delivered: delivered, idle: idle} = with_a_release(user, org, tmp_dir)

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives")
      |> click_link("#archive-tabs a", "Not delivered")
      |> assert_has("#archive-#{idle.uuid}")
      |> refute_has("#archive-#{delivered.uuid}")
      |> click_link("#archive-tabs a", "Delivered")
      |> assert_has("#archive-#{delivered.uuid}")
      |> refute_has("#archive-#{idle.uuid}")
    end

    test "searches and filters, and says when nothing matches", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      %{product: product, delivered: delivered, idle: idle} = with_a_release(user, org, tmp_dir)

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives?search=modem")
      |> assert_has("#archive-#{idle.uuid}")
      |> refute_has("#archive-#{delivered.uuid}")
      |> visit("/org/#{org.name}/#{product.name}/archives?search=modem&platform=rpi4")
      |> assert_has("#archive-no-matches", text: "No archive matches modem on rpi4")
      |> click_link("#archive-no-matches a", "Clear platform")
      |> assert_has("#archive-#{idle.uuid}")
    end

    test "the filter form patches the list", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      %{product: product, delivered: delivered, idle: idle} = with_a_release(user, org, tmp_dir)

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives")
      |> unwrap(&render_change(&1, "filter", %{"search" => "", "platform" => "rpi4"}))
      |> assert_path("/org/#{org.name}/#{product.name}/archives", query_params: %{platform: "rpi4"})
      |> assert_has("#archive-#{delivered.uuid}")
      |> refute_has("#archive-#{idle.uuid}")
    end
  end

  describe "show" do
    test "shows the archive and who gets it", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      %{product: product, delivered: delivered} = with_a_release(user, org, tmp_dir)

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives/#{delivered.uuid}")
      |> assert_has("h1", text: delivered.version)
      |> assert_has("#archive-uuid", text: delivered.uuid)
      |> assert_has("#archive-gets-it-now", text: "1")
      |> assert_has("#archive-gets-it-after-updating", text: "0")
      |> assert_has("[id^='delivery-']", text: "Fleet")
      |> assert_has("#archive-delete-note", text: "Releases in Fleet use this archive")
      |> assert_has("[role='row']", text: "Current release")
      |> assert_has("button[aria-label='Delete archive'][disabled]")
    end

    test "says when no group delivers it", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      %{product: product, idle: idle} = with_a_release(user, org, tmp_dir)

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives/#{idle.uuid}")
      |> assert_has("#no-delivery", text: "No deployment group’s current release includes it")
      |> refute_has("#archive-delete-note")
    end

    test "offers a download to a member who can download archives", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives/#{archive.uuid}")
      |> assert_has("a", text: "Download")
    end

    test "a view member isn't offered a download or delete", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      NervesHub.Repo.update_all(OrgUser, set: [role: :view])

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives/#{archive.uuid}")
      |> assert_has("h1", text: archive.version)
      |> refute_has("a", text: "Download")
      |> refute_has("button[aria-label='Delete archive']")
    end

    test "deletes the archive once confirmed", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives/#{archive.uuid}")
      |> click_button("button[aria-label='Delete archive']", "Delete")
      |> assert_has("#delete-archive-dialog-subtitle", text: archive.uuid)
      |> assert_has("#delete-archive-dialog", text: "The file is removed for good.")
      |> within("#delete-archive-dialog", &click_button(&1, "Delete archive"))
      |> assert_path("/org/#{org.name}/#{product.name}/archives")
      |> assert_has("div", text: "Manifest #{archive.version} was deleted")
      |> assert_has("#archives-empty")
    end

    test "a release made while the dialog is open stops the delete", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      session =
        conn
        |> visit("/org/#{org.name}/#{product.name}/archives/#{archive.uuid}")
        |> click_button("button[aria-label='Delete archive']", "Delete")

      deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user, name: "Late"})
      {:ok, _} = ManagedDeployments.create_deployment_release(deployment_group, firmware, archive, user, %{})

      session
      |> within("#delete-archive-dialog", &click_button(&1, "Delete archive"))
      |> assert_has("#delete-archive-dialog", text: "Releases in Late use this archive")
      |> refute_has("#delete-archive-dialog button", text: "Delete archive")
      |> assert_has("h1", text: archive.version)
    end
  end

  describe "the row menu" do
    test "deletes an archive once confirmed", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})
      other = Fixtures.archive_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives")
      |> refute_has("#delete-archive-dialog")
      |> click_button("#archive-#{archive.uuid} [role='menuitem']", "Delete…")
      |> assert_has("#delete-archive-dialog h2", text: archive.version)
      |> assert_has("#delete-archive-dialog", text: "No release has ever used it")
      |> within("#delete-archive-dialog", &click_button(&1, "Delete archive"))
      |> refute_has("#delete-archive-dialog")
      |> refute_has("#archive-#{archive.uuid}")
      |> assert_has("#archive-#{other.uuid}")
    end

    test "a delete that fails for another reason can be tried again", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      stub(Archives, :delete_archive, fn _archive -> {:error, Ecto.Changeset.change(archive)} end)

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives")
      |> click_button("#archive-#{archive.uuid} [role='menuitem']", "Delete…")
      |> within("#delete-archive-dialog", &click_button(&1, "Delete archive"))
      |> assert_has("div", text: "Manifest #{archive.version} couldn’t be deleted. Try again.")
      |> assert_has("#delete-archive-dialog button", text: "Delete archive")
      |> assert_has("#archive-#{archive.uuid}")
    end

    test "cancelling leaves the archive alone", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives")
      |> click_button("#archive-#{archive.uuid} [role='menuitem']", "Delete…")
      |> assert_has("#delete-archive-dialog")
      |> unwrap(&render_click(&1, "cancel-delete", %{}))
      |> refute_has("#delete-archive-dialog")
      |> assert_has("#archive-#{archive.uuid}")
    end

    test "says why an archive a release used can't be deleted", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      %{product: product, delivered: delivered} = with_a_release(user, org, tmp_dir)

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives")
      |> assert_has("#archive-#{delivered.uuid} button[role='menuitem'][disabled]", text: "It’s in releases of Fleet.")
    end

    test "a view member isn't offered delete", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      NervesHub.Repo.update_all(OrgUser, set: [role: :view])

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives")
      |> assert_has("#archive-#{archive.uuid}")
      |> refute_has("#archive-#{archive.uuid} [role='menuitem']", text: "Delete…")
      |> refute_has("#archive-form")
    end

    test "a view member can't delete by sending the event", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      NervesHub.Repo.update_all(OrgUser, set: [role: :view])

      session = visit(conn, "/org/#{org.name}/#{product.name}/archives")

      Process.flag(:trap_exit, true)

      assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} =
               catch_exit(render_click(session.view, "delete-archive", %{"archive_uuid" => archive.uuid}))

      assert {:ok, _} = Archives.get(product, archive.uuid)
    end
  end

  describe "sort and paginate" do
    test "sorts by version and flips direction on a second click", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      _archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives")
      |> unwrap(&render_click(&1, "sort", %{"sort" => "version"}))
      |> assert_path("/org/#{org.name}/#{product.name}/archives",
        query_params: %{sort: "version", sort_direction: "desc"}
      )
      |> unwrap(&render_click(&1, "sort", %{"sort" => "version"}))
      |> assert_path("/org/#{org.name}/#{product.name}/archives",
        query_params: %{sort: "version", sort_direction: "asc"}
      )
    end

    test "pages through the list", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      _first = Fixtures.archive_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})
      _second = Fixtures.archive_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives")
      |> unwrap(&render_change(&1, "set-paginate-opts", %{"page-size" => "25"}))
      |> assert_has("#archive-pager", text: "1–2 of 2")
      |> visit("/org/#{org.name}/#{product.name}/archives?page_size=1&page_number=2")
      |> assert_has("#archive-pager", text: "2–2 of 2")
      |> unwrap(&render_click(&1, "paginate", %{"page" => "1"}))
      |> assert_has("#archive-pager", text: "1–1 of 2")
    end

    test "a page past the end shows the last page", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives?page_number=9")
      |> assert_has("#archive-#{archive.uuid}")
    end
  end

  describe "upload archive" do
    test "marks the new archive and points at a release", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
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
      |> upload("Upload archive", signed_archive_path)
      |> assert_path("/org/#{org.name}/#{product.name}/archives")
      |> assert_has("#archive-list [role='row'] span", text: "New")
      |> assert_has("#archive-list a", text: "Add to a group’s release…")
    end

    test "says a corrupt archive has a bad signature", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org, %{name: "CoolProduct"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      {:ok, signed_archive_path} =
        Support.Archives.create_signed_archive(org_key.name, "manifest", "signed-manifest", %{dir: tmp_dir})

      {:ok, corrupt_archive_path} = Fwup.corrupt_firmware_file(signed_archive_path, tmp_dir)

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives")
      |> upload("Upload archive", corrupt_archive_path)
      |> assert_has("[id^='upload-failure-']", text: "Bad signature")
      |> assert_has("[id^='upload-failure-']",
        text: "It’s corrupt, or isn’t signed with any of #{org.name}’s signing keys."
      )
      |> assert_has("[id^='upload-failure-'] a", text: "Signing keys")
    end

    test "says an archive signed with another key has a bad signature", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org, %{name: "CoolProduct"})
      _org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      Fwup.gen_key_pair("wrong", tmp_dir)

      {:ok, signed_archive_path} =
        Support.Archives.create_signed_archive("wrong", "manifest", "signed-manifest", %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives")
      |> upload("Upload archive", signed_archive_path)
      |> assert_has("[id^='upload-failure-']", text: "Bad signature")
    end

    test "says when the archive is already here", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org, %{name: "CoolProduct"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      {:ok, signed_archive_path} =
        Support.Archives.create_signed_archive(org_key.name, "manifest", "signed-manifest", %{dir: tmp_dir})

      {:ok, existing} = Archives.create(product, signed_archive_path)

      conn
      |> visit("/org/#{org.name}/#{product.name}/archives")
      |> upload("Upload archive", signed_archive_path)
      |> assert_has("[id^='upload-failure-']", text: "Already uploaded")
      |> assert_has("[id^='upload-failure-'] a", text: "Open #{existing.version}")
      |> unwrap(fn view ->
        view |> element("[id^='upload-failure-'] button[aria-label='Dismiss']") |> render_click()
      end)
      |> refute_has("[id^='upload-failure-']")
    end
  end

  # Two archives: Calibration tables, in Fleet's current release, and a modem
  # image no release has used. Fleet has one device, on the release firmware.
  defp with_a_release(user, org, tmp_dir) do
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})

    delivered =
      Fixtures.archive_fixture(org_key, product, %{
        description: "Calibration tables",
        version: "1.6.0",
        platform: "rpi4",
        dir: tmp_dir
      })

    idle =
      Fixtures.archive_fixture(org_key, product, %{
        description: "Modem firmware",
        version: "25.10.2",
        platform: "bbb",
        dir: tmp_dir
      })

    deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user, name: "Fleet"})

    {:ok, {_release, deployment_group}} =
      ManagedDeployments.create_deployment_release(deployment_group, firmware, delivered, user, %{})

    Fixtures.device_fixture(org, product, firmware, %{deployment_id: deployment_group.id})

    %{product: product, delivered: delivered, idle: idle}
  end
end
