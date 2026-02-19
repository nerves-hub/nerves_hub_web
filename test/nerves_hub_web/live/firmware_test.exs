defmodule NervesHubWeb.Live.FirmwareTest do
  use NervesHubWeb.ConnCase.Browser, async: false

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

    test "lists all firmwares", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("h1", text: "Firmware")
      |> assert_has("a", text: firmware.uuid)
    end

    test "refreshes the list of all firmware if a new firmware is uploaded", %{
      conn: conn,
      user: user,
      org: org
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)

      firmware = Fixtures.firmware_fixture(org_key, product)

      conn =
        conn
        |> visit("/org/#{org.name}/#{product.name}/firmware")
        |> assert_has("h1", text: "Firmware")
        |> assert_has("a", text: firmware.uuid)
        |> refute_has("p",
          text:
            "New firmware (#{firmware.version} - #{String.slice(firmware.uuid, 0..7)}) available for selection."
        )
        |> refute_has("p",
          text:
            "New firmware (#{firmware.version} - #{String.slice(firmware.uuid, 0..7)}) available for selection. Please go back to page 1 to view it."
        )

      new_firmware = Fixtures.firmware_fixture(org_key, product)

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
           org: org
         } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)

      firmware_1 = Fixtures.firmware_fixture(org_key, product)

      {:ok, firmware_2} =
        Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0"})
        |> Ecto.Changeset.change(%{
          inserted_at:
            NaiveDateTime.utc_now()
            |> NaiveDateTime.add(1, :day)
            |> NaiveDateTime.truncate(:second)
        })
        |> Repo.update()

      {:ok, firmware_3} =
        Fixtures.firmware_fixture(org_key, product, %{version: "3.0.0"})
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

      new_firmware = Fixtures.firmware_fixture(org_key, product)

      conn
      |> assert_has("p",
        text:
          "New firmware (#{new_firmware.version} - #{String.slice(new_firmware.uuid, 0..7)}) available for selection. Please go back to page 1 to view it."
      )
      |> refute_has("a", text: new_firmware.uuid)
    end
  end

  describe "show" do
    test "shows the firmware information", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> assert_has("h1", text: firmware.uuid)
    end

    test "delete firmware", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org, %{name: "AmazingProduct"})
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)

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
      org: org
    } do
      product = Fixtures.product_fixture(user, org, %{name: "AmazingProduct"})
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)

      # Create a deployment from the firmware
      Fixtures.deployment_group_fixture(firmware)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> assert_has("h1", text: firmware.uuid)
      |> click_button("Delete")
      |> assert_path("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> assert_has("div", text: "Firmware has associated deployments")
    end

    test "error deleting firmware when it has associated deployment releases", %{
      conn: conn,
      user: user,
      org: org
    } do
      product = Fixtures.product_fixture(user, org, %{name: "AmazingProduct"})
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      firmware2 = Fixtures.firmware_fixture(org_key, product)

      # Create a deployment from the firmware
      deployment = Fixtures.deployment_group_fixture(firmware)

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
      |> assert_has("div", text: "No matching product could be found.")
    end
  end
end
