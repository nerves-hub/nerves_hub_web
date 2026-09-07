defmodule NervesHubWeb.Live.FirmwareTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  alias NervesHub.Firmwares
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.Repo
  alias NervesHub.Support.Fwup

  describe "index" do
    test "shows 'no firmware yet' message", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("span", text: "#{product.name} doesn’t have any firmware yet")
    end

    test "lists all firmwares", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("h1", text: "Firmware")
      |> assert_has("a", text: firmware.uuid)
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
        |> assert_has("a", text: firmware.uuid)
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
      |> assert_has("a", text: new_firmware.uuid)
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
        |> assert_has("a", text: firmware_3.uuid)
        |> assert_has("a", text: firmware_2.uuid)
        |> assert_has("a", text: firmware_1.uuid)
        |> visit("/org/#{org.name}/#{product.name}/firmware?page_size=2&page_number=2")
        |> refute_has("a", text: firmware_3.uuid, timeout: 100)
        |> refute_has("a", text: firmware_2.uuid, timeout: 100)
        |> assert_has("a", text: firmware_1.uuid)

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> assert_has("p",
        text:
          "New firmware (#{new_firmware.version} - #{String.slice(new_firmware.uuid, 0..7)}) available for selection. Please go back to page 1 to view it."
      )
      |> refute_has("a", text: new_firmware.uuid)
    end
  end

  describe "show" do
    test "shows the firmware information", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> assert_has("h1", text: firmware.uuid)
    end

    test "delete firmware", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org, %{name: "AmazingProduct"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> assert_has("h1", text: firmware.uuid)
      |> click_button("Delete")
      |> assert_path("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("div", text: "Firmware successfully deleted")
      |> assert_has("span", text: "#{product.name} doesn’t have any firmware yet")
    end

    test "error deleting firmware when it has associated deployments", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org, %{name: "AmazingProduct"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      # Create a deployment from the firmware
      Fixtures.deployment_group_fixture(firmware, %{user: user})

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> assert_has("h1", text: firmware.uuid)
      |> click_button("Delete")
      |> assert_path("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> assert_has("div", text: "Firmware has associated deployment releases")
    end

    test "error deleting firmware when it has associated deployment releases", %{
      conn: conn,
      user: user,
      org: org,
      tmp_dir: tmp_dir
    } do
      product = Fixtures.product_fixture(user, org, %{name: "AmazingProduct"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      firmware2 = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      # Create a deployment from the firmware
      deployment = Fixtures.deployment_group_fixture(firmware, %{user: user})

      ManagedDeployments.update_deployment_group(deployment, %{firmware_id: firmware2.id}, user)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> assert_has("h1", text: firmware.uuid)
      |> click_button("Delete")
      |> assert_path("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> assert_has("p",
        text: "Error deleting firmware: Firmware has associated deployment releases"
      )
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
        |> assert_has("h1", text: firmware.uuid)
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
      |> assert_has("h1", text: firmware.uuid)
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
      |> assert_has("a", text: firmware.uuid)
      |> unwrap(fn view ->
        render_change(view, "paginate", %{"page" => "1"})
      end)
      |> assert_has("h1", text: "Firmware")
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
      |> assert_has("a", text: firmware_1.uuid)
      |> assert_has("a", text: firmware_2.uuid)
      |> tap(fn _ -> Firmwares.delete_firmware(firmware_2) end)
      |> assert_has("p", text: "has been deleted by another user.")
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
      |> upload("Upload Firmware", signed_firmware_path)
      |> assert_path("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("div", text: "Firmware uploaded")
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
      |> upload("Upload Firmware", corrupt_firmware_path)
      |> assert_path("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("div", text: "Firmware corrupt, signature invalid, or missing public key")
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
      |> upload("Upload Firmware", signed_firmware_path)
      |> assert_path("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("div", text: "Firmware corrupt, signature invalid, or missing public key")
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
      |> upload("Upload Firmware", signed_firmware_path)
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
      |> upload("Upload Firmware", signed_firmware_path)
      |> assert_has("div", text: "Firmware uploaded successfully")
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
      |> assert_has("a", text: firmware.uuid)
      |> unwrap(fn view ->
        render_click(view, "delete-firmware", %{"firmware_uuid" => firmware.uuid})
      end)
      |> assert_has("div", text: "Firmware successfully deleted")
      |> refute_has("a", text: firmware.uuid)
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

      stub(Firmwares, :delete_firmware, fn _ ->
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
      |> assert_has("a", text: firmware.uuid)
      |> unwrap(fn view ->
        render_click(view, "delete-firmware", %{"firmware_uuid" => firmware.uuid})
      end)
      |> assert_has("div", text: "firmware has deployments", exact: false)
    end
  end

  describe "firmware-selected event" do
    test "is a noop", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      _firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> unwrap(fn view ->
        render_click(view, "firmware-selected", %{})
      end)
      |> assert_has("h1", text: "Firmware")
    end
  end
end
