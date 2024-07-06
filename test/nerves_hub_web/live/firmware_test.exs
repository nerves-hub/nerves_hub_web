defmodule NervesHubWeb.Live.FirmwareTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures
  alias NervesHub.Support.Fwup

  describe "index" do
    test "shows 'no firmware yet' message", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("h3", text: "#{product.name} doesn’t have any firmware yet")
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

    test "delete firmware from list", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("h1", text: "Firmware")
      |> assert_has("a", text: firmware.uuid)
      |> click_link("Delete")
      |> assert_has("div", text: "Firmware successfully deleted")
      |> assert_has("h3", text: "#{product.name} doesn’t have any firmware yet")
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
      Fixtures.deployment_fixture(org, firmware)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("h1", text: "Firmware")
      |> assert_has("a", text: firmware.uuid)
      |> click_link("Delete")
      |> assert_path("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("div", text: "Firmware has associated deployments")
    end
  end

  describe "show" do
    test "shows the firmware information", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> assert_has("h1", text: "Firmware #{firmware.version}")
    end

    test "delete firmware", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org, %{name: "AmazingProduct"})
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> assert_has("h1", text: "Firmware #{firmware.version}")
      |> click_link("Delete")
      |> assert_path("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("div", text: "Firmware successfully deleted")
      |> assert_has("h3", text: "#{product.name} doesn’t have any firmware yet")
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
      Fixtures.deployment_fixture(org, firmware)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> assert_has("h1", text: "Firmware #{firmware.version}")
      |> click_link("Delete")
      |> assert_path("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> assert_has("div", text: "Firmware has associated deployments")
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
      |> visit("/org/#{org.name}/#{product.name}/firmware/upload")
      |> assert_has("h1", text: "Add Firmware")
      |> unwrap(fn view ->
        file_input(view, "form", :firmware, [
          %{
            name: "signed.fw",
            content: File.read!(signed_firmware_path)
          }
        ])
        |> render_upload("signed.fw")

        render(view)
      end)
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
      |> visit("/org/#{org.name}/#{product.name}/firmware/upload")
      |> assert_has("h1", text: "Add Firmware")
      |> unwrap(fn view ->
        file_input(view, "form", :firmware, [
          %{
            name: "signed.fw",
            content: File.read!(corrupt_firmware_path)
          }
        ])
        |> render_upload("signed.fw")

        render(view)
      end)
      |> assert_path("/org/#{org.name}/#{product.name}/firmware/upload")
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
      |> visit("/org/#{org.name}/#{product.name}/firmware/upload")
      |> assert_has("h1", text: "Add Firmware")
      |> unwrap(fn view ->
        file_input(view, "form", :firmware, [
          %{
            name: "signed.fw",
            content: File.read!(signed_firmware_path)
          }
        ])
        |> render_upload("signed.fw")

        render(view)
      end)
      |> assert_path("/org/#{org.name}/#{product.name}/firmware/upload")
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
      |> visit("/org/#{org.name}/#{product.name}/firmware/upload")
      |> assert_has("h1", text: "Add Firmware")
      |> unwrap(fn view ->
        file_input(view, "form", :firmware, [
          %{
            name: "signed.fw",
            content: File.read!(signed_firmware_path)
          }
        ])
        |> render_upload("signed.fw")

        render(view)
      end)
      |> assert_path("/org/#{org.name}/#{product.name}/firmware/upload")
      |> assert_has("div", text: "No matching product could be found.")
    end
  end
end
