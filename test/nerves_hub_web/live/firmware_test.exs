defmodule NervesHubWeb.Live.FirmwareTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  alias NervesHub.Accounts
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Firmwares
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.Repo
  alias NervesHub.Support.Fwup

  describe "index" do
    test "shows how to upload the first firmware", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("#firmware-empty h2", text: "Upload your first firmware")
      |> assert_has("#firmware-empty", text: "#{product.name} doesn’t have any firmware yet.")
      |> refute_has("#firmware-tabs")
    end

    test "lists all firmwares", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("h1", text: "Firmware")
      |> assert_has("#firmware-#{firmware.uuid} a[title='#{firmware.uuid}']", text: firmware.version)
      |> assert_has("#firmware-#{firmware.uuid}", text: org_key.name)
      |> assert_has("#firmware-#{firmware.uuid}", text: "Not running")
    end

    test "says which deployment groups use a firmware", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      group = Fixtures.deployment_group_fixture(firmware, %{user: user})

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("#firmware-#{firmware.uuid} a", text: group.name)
      |> assert_has("#firmware-#{firmware.uuid}", text: "current release")
    end

    test "splits firmware by whether it's in use", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      running = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      idle = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "2.0.0"})
      _device = Fixtures.device_fixture(org, product, running)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> click_link("#firmware-tabs a", "In use")
      |> assert_has("#firmware-#{running.uuid}", text: "1")
      |> refute_has("#firmware-#{idle.uuid}")
      |> click_link("#firmware-tabs a", "Not in use")
      |> assert_has("#firmware-#{idle.uuid}")
      |> refute_has("#firmware-#{running.uuid}")
    end

    test "searches and filters, and says when nothing matches", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      first = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      second =
        Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "2.5.0", platform: "taramasalata"})

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> fill_in("Search firmware", with: "2.5")
      |> assert_has("#firmware-#{second.uuid}")
      |> refute_has("#firmware-#{first.uuid}")
      |> fill_in("Search firmware", with: "9.9")
      |> assert_has("#firmware-no-matches", text: "No firmware matches")
      |> assert_has("#firmware-no-matches", text: "9.9")
      |> click_link("Clear search")
      |> assert_has("#firmware-#{first.uuid}")
      |> assert_has("#firmware-#{second.uuid}")
      # PhoenixTest keeps what was typed into a form across steps, so the
      # platform filter starts from a fresh page.
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> select("Platform", option: "taramasalata", exact: false)
      |> assert_has("#firmware-#{second.uuid}")
      |> refute_has("#firmware-#{first.uuid}")
    end

    test "refreshes the list of all firmware if a new firmware is uploaded", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn =
        conn
        |> visit("/org/#{org.name}/#{product.name}/firmware")
        |> assert_has("h1", text: "Firmware")
        |> assert_has("#firmware-#{firmware.uuid}")
        |> refute_has("p",
          text: "New firmware (#{firmware.version} - #{String.slice(firmware.uuid, 0..7)}) available for selection."
        )
        |> refute_has("p",
          text:
            "New firmware (#{firmware.version} - #{String.slice(firmware.uuid, 0..7)}) available for selection. Please go back to page 1 to view it."
        )

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> assert_has("p",
        text:
          "New firmware (#{new_firmware.version} - #{String.slice(new_firmware.uuid, 0..7)}) available for selection."
      )
      |> refute_has("p",
        text:
          "New firmware (#{new_firmware.version} - #{String.slice(new_firmware.uuid, 0..7)}) available for selection. Please go back to page 1 to view it."
      )
      |> assert_has("#firmware-#{new_firmware.uuid}")
    end

    test "if you are not on the first page of firmware, a flash message if a new firmware is uploaded",
         %{
           conn: conn,
           user: user,
           org: org,
           tmp_dir: tmp_dir
         } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      firmware_1 = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      {:ok, firmware_2} =
        Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})
        |> Ecto.Changeset.change(%{
          inserted_at:
            NaiveDateTime.utc_now()
            |> NaiveDateTime.add(1, :day)
            |> NaiveDateTime.truncate(:second)
        })
        |> Repo.update()

      {:ok, firmware_3} =
        Fixtures.firmware_fixture(org_key, product, %{version: "3.0.0", dir: tmp_dir})
        |> Ecto.Changeset.change(%{
          inserted_at:
            NaiveDateTime.utc_now()
            |> NaiveDateTime.add(2, :day)
            |> NaiveDateTime.truncate(:second)
        })
        |> Repo.update()

      conn =
        conn
        |> visit("/org/#{org.name}/#{product.name}/firmware")
        |> assert_has("h1", text: "Firmware")
        |> assert_has("#firmware-#{firmware_3.uuid}")
        |> assert_has("#firmware-#{firmware_2.uuid}")
        |> assert_has("#firmware-#{firmware_1.uuid}")
        |> visit("/org/#{org.name}/#{product.name}/firmware?page_size=2&page_number=2")
        |> refute_has("#firmware-#{firmware_3.uuid}", timeout: 100)
        |> refute_has("#firmware-#{firmware_2.uuid}", timeout: 100)
        |> assert_has("#firmware-#{firmware_1.uuid}")

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> assert_has("p",
        text:
          "New firmware (#{new_firmware.version} - #{String.slice(new_firmware.uuid, 0..7)}) available for selection. Please go back to page 1 to view it."
      )
      |> refute_has("#firmware-#{new_firmware.uuid}")
    end

    test "deleted firmware is only on the Deleted tab", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org, %{name: "ShowDeletedProduct"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      kept = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      removed = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "1.0.1"})

      {:ok, _} = Firmwares.delete_firmware(removed, user)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("#firmware-#{kept.uuid}")
      |> refute_has("#firmware-#{removed.uuid}")
      |> click_link("#firmware-tabs a", "Deleted")
      |> assert_path("/org/#{org.name}/#{product.name}/firmware", query_params: %{tab: "deleted"})
      |> assert_has("#deleted-firmware-#{removed.id}", text: "File removed")
      |> assert_has("#deleted-firmware-#{removed.id}", text: "by #{user.name}")
      # Still linked, so history does not dead-end.
      |> assert_has("#deleted-firmware-#{removed.id} a[title='#{removed.uuid}']")
      |> refute_has("#firmware-#{kept.uuid}")
      |> refute_has("#deleted-firmware-#{kept.id}")
    end

    test "a build deleted twice has a row for each deletion on the Deleted tab", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      {:ok, first} = Firmwares.delete_firmware(firmware, user)

      # The same file uploaded again and deleted again: the UUID is only
      # unique among firmware that isn't deleted.
      second =
        first
        |> Map.put(:id, nil)
        |> Ecto.put_meta(state: :built)
        |> Repo.insert!()

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware?tab=deleted")
      |> assert_has("#deleted-firmware-#{first.id}", text: firmware.version)
      |> assert_has("#deleted-firmware-#{second.id}", text: firmware.version)
    end
  end

  describe "show" do
    test "shows the firmware information", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> assert_has("nav[aria-label='Breadcrumb']", text: firmware.version)
      |> assert_has("h1", text: firmware.version)
      |> assert_has("#firmware-uuid", text: firmware.uuid)
      |> assert_has("#firmware-running", text: "0")
      |> assert_has("#firmware-installed", text: "0")
      |> assert_has("#no-releases", text: "No deployment group releases it.")
      |> assert_has("aside", text: firmware.author)
      |> assert_has("aside", text: firmware.vcs_identifier)
    end

    test "shows the groups releasing it, its deltas and its other builds", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      older = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "0.9.0"})
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "1.0.0"})
      sibling = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "1.0.0", platform: "rpi3"})

      group = Fixtures.deployment_group_fixture(firmware, %{user: user, name: "Production Fleet"})

      _device =
        org
        |> Fixtures.device_fixture(product, firmware)
        |> Ecto.Changeset.change(deployment_id: group.id)
        |> Repo.update!()

      delta = Fixtures.firmware_delta_fixture(older, firmware)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> assert_has("#firmware-running", text: "1")
      |> assert_has("#release-#{group.id}", text: "Production Fleet")
      |> assert_has("#release-#{group.id}", text: "current release")
      |> assert_has("#release-#{group.id}", text: "1 of 1 device")
      |> assert_has("#delta-#{delta.id}", text: older.version)
      |> assert_has("#delta-#{delta.id}", text: "50%")
      |> assert_has("#delta-#{delta.id}", text: "Ready")
      |> assert_has("#other-builds a[href$='/firmware/#{sibling.uuid}']", text: "rpi3")
      |> assert_has("#firmware-delete-note", text: "This firmware is the current release of Production Fleet")
    end

    test "retries a failed delta", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      older = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "0.9.0"})
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "1.0.0"})

      delta = Fixtures.firmware_delta_fixture(older, firmware)
      {:ok, _} = delta |> Ecto.Changeset.change(status: :failed) |> Repo.update()

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> assert_has("#delta-#{delta.id}", text: "Failed")
      |> click_button("#delta-#{delta.id} button", "Retry")
      |> assert_has("[role='alert']", text: "Building the delta from #{older.version} again")
      |> assert_has("[id^='delta-']", text: "Building")
    end

    test "says so when a failed delta can't be started again", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      older = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "0.9.0"})
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "1.0.0"})

      delta = Fixtures.firmware_delta_fixture(older, firmware)
      {:ok, _} = delta |> Ecto.Changeset.change(status: :failed) |> Repo.update()

      stub(Firmwares, :retry_firmware_delta, fn _delta -> {:error, :failed_to_insert_job} end)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> click_button("#delta-#{delta.id} button", "Retry")
      |> assert_has("[role='alert']", text: "Couldn't start building the delta from #{older.version}")
      |> assert_has("#delta-#{delta.id}", text: "Failed")
    end

    test "delete firmware", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org, %{name: "AmazingProduct"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> click_button("button[aria-label='Delete firmware']", "Delete")
      |> assert_has("#delete-firmware-dialog",
        text: "The file is removed and can’t be downloaded or sent to devices again."
      )
      |> click_button("#delete-firmware-dialog button", "Delete firmware")
      |> assert_path("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("div", text: "Firmware successfully deleted")
      |> assert_has("#firmware-no-matches", text: "This product has no firmware that isn’t deleted.")
    end

    test "the delete button is disabled, with a reason, when a deployment group is on this firmware", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org, %{name: "AmazingProduct"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> assert_has("button[aria-label='Delete firmware'][disabled]")
      |> assert_has("#firmware-delete-note", text: "This firmware is the current release of #{deployment_group.name}")
    end

    test "deletes firmware that only a past release references", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org, %{name: "AmazingProduct"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      firmware2 = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      deployment = Fixtures.deployment_group_fixture(firmware, %{user: user})

      # A second release moves the group on, leaving the first firmware
      # referenced only by history.
      {:ok, _} = ManagedDeployments.create_deployment_release(deployment, firmware2, nil, user, %{})

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> refute_has("button[aria-label='Delete firmware'][disabled]")
      |> refute_has("#firmware-delete-note")
      |> assert_has("#release-#{deployment.id}", text: "previous release")
      |> click_button("button[aria-label='Delete firmware']", "Delete")
      |> click_button("#delete-firmware-dialog button", "Delete firmware")
      |> assert_path("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("div", text: "Firmware successfully deleted")
    end

    test "a view member isn't offered a download", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      Repo.update_all(OrgUser, set: [role: :view])

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> assert_has("h1", text: firmware.version)
      |> refute_has("a", text: "Download")
    end

    test "a deleted firmware's page says who deleted it, and offers no download", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org, %{name: "AmazingProduct"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      {:ok, _} = Firmwares.delete_firmware(firmware, user)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> assert_has("h1", text: firmware.version)
      |> assert_has("#firmware-deleted", text: "This firmware was deleted by #{user.name}")
      |> refute_has("button[aria-label='Delete firmware']")
      |> refute_has("a", text: "Download")
    end

    test "only members who can download firmware are offered it", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org, %{name: "AmazingProduct"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      page = "/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}"

      conn
      |> visit(page)
      |> assert_has("a", text: "Download")

      {:ok, org_user} = Accounts.get_org_user(org, user)
      {:ok, _} = Accounts.change_org_user_role(org_user, :view)

      conn
      |> visit(page)
      |> refute_has("a", text: "Download")

      assert_error_sent(401, fn ->
        get(conn, "/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}/download")
      end)
    end

    test "no flash is shown when new firmware is uploaded",
         %{
           conn: conn,
           user: user,
           org: org,
           tmp_dir: tmp_dir
         } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn =
        conn
        |> visit("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
        |> assert_has("h1", text: firmware.version)
        |> refute_has("p",
          text: "New firmware (#{firmware.version} - #{String.slice(firmware.uuid, 0..7)}) available for selection."
        )
        |> refute_has("p",
          text:
            "New firmware (#{firmware.version} - #{String.slice(firmware.uuid, 0..7)}) available for selection. Please go back to page 1 to view it."
        )

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> refute_has("p",
        text:
          "New firmware (#{new_firmware.version} - #{String.slice(new_firmware.uuid, 0..7)}) available for selection."
      )
      |> refute_has("p",
        text:
          "New firmware (#{new_firmware.version} - #{String.slice(new_firmware.uuid, 0..7)}) available for selection. Please go back to page 1 to view it."
      )
    end

    test "no flash is show when other firmware is deleted",
         %{
           conn: conn,
           user: user,
           org: org,
           tmp_dir: tmp_dir
         } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      other_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> assert_has("h1", text: firmware.version)
      |> refute_has("p", text: "has been deleted by another user.")
      |> tap(fn _ -> Firmwares.delete_firmware(other_firmware) end)
      |> refute_has("p", text: "has been deleted by another user.")
    end
  end

  describe "sort and paginate" do
    test "sort by a new column", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      _firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("h1", text: "Firmware")
      |> unwrap(fn view ->
        render_change(view, "sort", %{"sort" => "version"})
      end)
      |> assert_has("h1", text: "Firmware")
    end

    test "sort by the same column toggles direction", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      _firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware?sort=inserted_at&sort_direction=asc")
      |> assert_has("h1", text: "Firmware")
      |> unwrap(fn view ->
        render_change(view, "sort", %{"sort" => "inserted_at"})
      end)
      |> assert_has("h1", text: "Firmware")
    end

    test "paginate to another page", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware?page_size=1")
      |> assert_has("#firmware-#{firmware.uuid}")
      |> unwrap(fn view ->
        render_change(view, "paginate", %{"page" => "1"})
      end)
      |> assert_has("h1", text: "Firmware")
    end

    test "the footer says which firmware is shown and pages through it", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      _first = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      _second = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware?page_size=1")
      |> assert_has("#firmware-pager", text: "1–1 of 2")
      |> assert_has("#firmware-pager", text: "1 / 2")
      |> assert_has("#firmware-pager button[aria-label='Previous page'][disabled]")
      |> unwrap(fn view ->
        view
        |> element("#firmware-pager button[aria-label='Next page']")
        |> render_click()
      end)
      |> assert_has("#firmware-pager", text: "2–2 of 2")
      |> assert_has("#firmware-pager button[aria-label='Next page'][disabled]")
      |> select("Firmware per page", option: "50")
      |> assert_has("#firmware-pager", text: "1–2 of 2")
    end

    test "change page size", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      _firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("h1", text: "Firmware")
      |> unwrap(fn view ->
        render_change(view, "set-paginate-opts", %{"page-size" => "50"})
      end)
      |> assert_has("h1", text: "Firmware")
    end
  end

  describe "firmware deleted by another user (index)" do
    test "shows a flash when firmware is deleted while viewing the index", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware_1 = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      firmware_2 = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("#firmware-#{firmware_1.uuid}")
      |> assert_has("#firmware-#{firmware_2.uuid}")
      |> tap(fn _ -> Firmwares.delete_firmware(firmware_2) end)
      |> assert_has("p", text: "has been deleted by another user.")
      |> refute_has("#firmware-#{firmware_2.uuid}")
    end
  end

  describe "upload firmware" do
    test "redirects after successful upload", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org, %{name: "CoolProduct"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      {:ok, signed_firmware_path} =
        Fwup.create_signed_firmware(org_key.name, "unsigned", "signed", %{
          product: product.name,
          dir: tmp_dir
        })

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> upload("Upload firmware", signed_firmware_path)
      |> assert_path("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("#firmware-list [role='row'] span", text: "New")
      |> assert_has("h1", text: "Firmware")
    end

    test "error if corrupt firmware uploaded", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org, %{name: "CoolProduct"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      {:ok, signed_firmware_path} =
        Fwup.create_signed_firmware(org_key.name, "unsigned", "signed", %{
          product: product.name,
          dir: tmp_dir
        })

      {:ok, corrupt_firmware_path} = Fwup.corrupt_firmware_file(signed_firmware_path, tmp_dir)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> upload("Upload firmware", corrupt_firmware_path)
      |> assert_path("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("[id^='upload-failure-']", text: "Bad signature")
      |> assert_has("[id^='upload-failure-']", text: "Firmware corrupt, signature invalid, or missing public key")
      |> assert_has("[id^='upload-failure-'] a", text: "Signing keys")
    end

    test "error if the organization has no signing keys", %{conn: conn, user: user, tmp_dir: tmp_dir} do
      org = Fixtures.org_fixture(user, %{name: "KeylessOrg"})
      product = Fixtures.product_fixture(user, org, %{name: "CoolProduct"})

      Fwup.gen_key_pair("unregistered", tmp_dir)

      {:ok, signed_firmware_path} =
        Fwup.create_signed_firmware("unregistered", "unsigned", "signed", %{
          product: product.name,
          dir: tmp_dir
        })

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> upload("Upload firmware", signed_firmware_path)
      |> assert_has("[id^='upload-failure-']", text: "No signing keys")
      |> assert_has("[id^='upload-failure-']", text: "Please register public keys")
      |> refute_has("[id^='upload-failure-']", text: "Bad signature")
    end

    test "error if org keys do not match firmware", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org, %{name: "CoolProduct"})

      Fwup.gen_key_pair("wrong", tmp_dir)

      {:ok, signed_firmware_path} =
        Fwup.create_signed_firmware("wrong", "unsigned", "signed", %{
          product: product.name,
          dir: tmp_dir
        })

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> upload("Upload firmware", signed_firmware_path)
      |> assert_path("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("div", text: "Firmware corrupt, signature invalid, or missing public key")
    end

    test "error if the firmware requires a newer fwup", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org, %{name: "CoolProduct"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      {:ok, _} = Fwup.create_firmware(tmp_dir, "unsigned", %{product: product.name})
      {:ok, _} = Fwup.require_newer_fwup(tmp_dir, "unsigned", "newer")
      {:ok, signed_path} = Fwup.sign_firmware(tmp_dir, org_key.name, "newer", "signed")

      # The message names the instance as it's configured.
      previous = Application.get_env(:nerves_hub, :friendly_platform_name)
      Application.put_env(:nerves_hub, :friendly_platform_name, "NervesCloud")
      on_exit(fn -> Application.put_env(:nerves_hub, :friendly_platform_name, previous) end)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> upload("Upload firmware", signed_path)
      |> assert_path("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("div", text: "This firmware requires fwup 99.0.0 or newer, and NervesCloud has fwup")
      |> assert_has("div", text: "Please contact support to have NervesCloud's fwup updated.")
    end

    # Previously this reported "No matching product could be found", which
    # pointed at the wrong thing: the problem is not that AnotherProduct is
    # missing, it is that this firmware was uploaded to the wrong product.
    test "error if meta-product does not match product name", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org, %{name: "CoolProduct"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      {:ok, signed_firmware_path} =
        Fwup.create_signed_firmware(org_key.name, "unsigned", "signed", %{
          product: "AnotherProduct",
          dir: tmp_dir
        })

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> upload("Upload firmware", signed_firmware_path)
      |> assert_path("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("div", text: "AnotherProduct")
      |> assert_has("div", text: "CoolProduct")
    end

    # The same firmware uploaded to the product it was built for still works —
    # the check must not reject a legitimate upload.
    test "uploads firmware whose meta-product matches the product", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org, %{name: "CoolProduct"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      {:ok, signed_firmware_path} =
        Fwup.create_signed_firmware(org_key.name, "unsigned", "signed", %{
          product: "CoolProduct",
          dir: tmp_dir
        })

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> upload("Upload firmware", signed_firmware_path)
      |> assert_has("#firmware-list [role='row'] span", text: "New")
      |> refute_has("[id^='upload-failure-']")
    end
  end

  describe "delete from index" do
    test "deletes firmware from list page via event", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org, %{name: "DeleteIndexProduct"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("#firmware-#{firmware.uuid}")
      |> unwrap(fn view ->
        render_click(view, "delete-firmware", %{"firmware_uuid" => firmware.uuid})
      end)
      |> assert_has("div", text: "Firmware successfully deleted")
      |> refute_has("#firmware-#{firmware.uuid}")
    end

    test "deleting the only row on the last page shows the page before it", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      newer = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "1.0.2"})
      middle = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "1.0.1"})
      oldest = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, version: "1.0.0"})

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware?sort=version&sort_direction=desc&page_size=2&page_number=2")
      |> assert_has("#firmware-#{oldest.uuid}")
      |> unwrap(&render_click(&1, "delete-firmware", %{"firmware_uuid" => oldest.uuid}))
      |> assert_has("div", text: "Firmware successfully deleted")
      |> assert_has("#firmware-#{newer.uuid}")
      |> assert_has("#firmware-#{middle.uuid}")
      |> refute_has("#firmware-no-matches")
      |> assert_has("button[aria-label='Next page'][disabled]")
    end

    test "shows error when delete fails (list page)", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org, %{name: "DeleteErrorFirmwareProduct"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      stub(Firmwares, :delete_firmware, fn _firmware, _user ->
        {:error,
         %Ecto.Changeset{
           errors: [base: {"firmware has deployments", []}],
           data: %{},
           changes: %{},
           types: %{},
           valid?: false
         }}
      end)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("#firmware-#{firmware.uuid}")
      |> unwrap(fn view ->
        render_click(view, "delete-firmware", %{"firmware_uuid" => firmware.uuid})
      end)
      |> assert_has("div", text: "firmware has deployments", exact: false)
    end
  end

  describe "delete dialog" do
    test "deletes a firmware from its row's menu, once confirmed", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      _device = Fixtures.device_fixture(org, product, firmware)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> refute_has("#delete-firmware-dialog")
      |> click_button("#firmware-#{firmware.uuid} [role='menuitem']", "Delete…")
      |> assert_has("#delete-firmware-dialog h2",
        text: "Delete #{firmware.version} for #{firmware.platform} · #{firmware.architecture}?"
      )
      |> assert_has("#delete-firmware-dialog-subtitle", text: firmware.uuid)
      |> assert_has("#delete-firmware-dialog li", text: "1 device is running it")
      |> refute_has("#delete-firmware-dialog li", text: "deleted too")
      |> within("#delete-firmware-dialog", &click_button(&1, "Delete firmware"))
      |> assert_has("div", text: "Firmware successfully deleted")
      |> refute_has("#delete-firmware-dialog")
      |> refute_has("#firmware-#{firmware.uuid}")
    end

    test "says how many deltas built from it go with it", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})
      newer = Fixtures.firmware_fixture(org_key, product, %{version: "1.1.0", dir: tmp_dir})
      _delta = Fixtures.firmware_delta_fixture(firmware, newer)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> click_button("#firmware-#{firmware.uuid} [role='menuitem']", "Delete…")
      |> assert_has("#delete-firmware-dialog li", text: "No device is running it")
      |> assert_has("#delete-firmware-dialog li", text: "1 delta built from it is deleted too")
    end

    test "cancelling leaves the firmware alone", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> click_button("#firmware-#{firmware.uuid} [role='menuitem']", "Delete…")
      |> assert_has("#delete-firmware-dialog")
      |> unwrap(&render_click(&1, "cancel-delete", %{}))
      |> refute_has("#delete-firmware-dialog")
      |> assert_has("#firmware-#{firmware.uuid}")

      assert Firmwares.get_by_uuid(product, firmware.uuid)
    end

    test "a group's current release can't be deleted, and the menu says why", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      group = Fixtures.deployment_group_fixture(firmware, %{user: user})

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("#firmware-#{firmware.uuid} button[role='menuitem'][disabled]",
        text: "This firmware is the current release of #{group.name}"
      )
    end

    test "a view member isn't offered delete or a new deployment group", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      Repo.update_all(OrgUser, set: [role: :view])

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("#firmware-#{firmware.uuid} [role='menuitem']", text: "Copy UUID")
      |> refute_has("#firmware-#{firmware.uuid} [role='menuitem']", text: "Delete")
      |> refute_has("#firmware-#{firmware.uuid} [role='menuitem']", text: "New deployment group")
      |> refute_has("label", text: "Upload firmware")
    end
  end
end
