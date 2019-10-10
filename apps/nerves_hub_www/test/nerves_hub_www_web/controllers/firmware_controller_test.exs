defmodule NervesHubWWWWeb.FirmwareControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: true

  alias NervesHubWebCore.Fixtures
  alias NervesHubWebCore.Accounts
  alias NervesHubWebCore.Firmwares
  alias NervesHubWebCore.Support.Fwup

  describe "index" do
    test "lists all firmwares", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)

      conn = get(conn, Routes.firmware_path(conn, :index, org.name, product.name))
      assert html_response(conn, 200) =~ "Firmware"

      assert html_response(conn, 200) =~
               Routes.firmware_path(conn, :upload, org.name, product.name)
    end
  end

  describe "upload firmware form" do
    test "renders form with valid request params", %{
      conn: conn,
      user: user,
      org: org
    } do
      product = Fixtures.product_fixture(user, org)
      conn = get(conn, Routes.firmware_path(conn, :upload, org.name, product.name))

      assert html_response(conn, 200) =~ "Upload Firmware"

      assert html_response(conn, 200) =~
               Routes.firmware_path(conn, :do_upload, org.name, product.name)
    end
  end

  describe "upload firmware" do
    test "redirects after successful upload", %{
      conn: conn,
      user: user,
      org: org,
      org_key: org_key
    } do
      product_name = "cool product"
      product = Fixtures.product_fixture(user, org, %{name: product_name})

      {:ok, signed_firmware_path} =
        Fwup.create_signed_firmware(org_key.name, "unsigned", "signed", %{product: product_name})

      upload = %Plug.Upload{
        path: signed_firmware_path,
        filename: "doesnt_matter.fw"
      }

      # check that we end up in the right place
      create_conn =
        post(conn, Routes.firmware_path(conn, :upload, org.name, product.name), %{
          "firmware" => %{"file" => upload}
        })

      assert redirected_to(create_conn, 302) =~
               Routes.firmware_path(conn, :index, org.name, product.name)

      # check that the proper creation side effects took place
      conn = get(conn, Routes.firmware_path(conn, :index, org.name, product.name))
      # starter is the product for the test firmware
      assert html_response(conn, 200) =~ product_name
    end

    test "error if corrupt firmware uploaded", %{
      conn: conn,
      user: user,
      org: org,
      org_key: org_key
    } do
      product = Fixtures.product_fixture(user, org, %{name: "starter"})

      {:ok, signed_firmware_path} =
        Fwup.create_signed_firmware(org_key.name, "unsigned", "signed", %{product: "starter"})

      {:ok, corrupt_firmware_path} = Fwup.corrupt_firmware_file(signed_firmware_path)

      upload = %Plug.Upload{
        path: corrupt_firmware_path,
        filename: "doesnt_matter.fw"
      }

      # check for the error message
      conn =
        post(conn, Routes.firmware_path(conn, :upload, org.name, product.name), %{
          "firmware" => %{"file" => upload}
        })

      assert html_response(conn, 200) =~
               "Firmware corrupt, signature invalid or missing public key"
    end

    test "error if org keys do not match firmware", %{
      conn: conn,
      user: user,
      org: org
    } do
      product = Fixtures.product_fixture(user, org, %{name: "starter"})

      Fwup.gen_key_pair("wrong")

      {:ok, signed_firmware_path} =
        Fwup.create_signed_firmware("wrong", "unsigned", "signed", %{product: "starter"})

      upload = %Plug.Upload{
        path: signed_firmware_path,
        filename: "doesnt_matter.fw"
      }

      # check for the error message
      conn =
        post(conn, Routes.firmware_path(conn, :upload, org.name, product.name), %{
          "firmware" => %{"file" => upload}
        })

      assert html_response(conn, 200) =~
               "Firmware corrupt, signature invalid or missing public key"
    end

    test "error if meta-product does not match product name", %{
      conn: conn,
      user: user,
      org: org,
      org_key: org_key
    } do
      product = Fixtures.product_fixture(user, org, %{name: "non-matching name"})

      {:ok, signed_firmware_path} =
        Fwup.create_signed_firmware(org_key.name, "unsigned", "signed", %{product: "name"})

      upload = %Plug.Upload{
        path: signed_firmware_path,
        filename: "doesnt_matter.fw"
      }

      # check for the error message
      conn =
        post(conn, Routes.firmware_path(conn, :upload, org.name, product.name), %{
          "firmware" => %{"file" => upload}
        })

      assert html_response(conn, 200) =~ "No matching product could be found."
    end

    test "error if firmware size exceeds limit", %{
      conn: conn,
      user: user,
      org: org
    } do
      Accounts.create_org_limit(%{org_id: org.id, firmware_size: 1})
      product = Fixtures.product_fixture(user, org, %{name: "starter"})
      org_key = Fixtures.org_key_fixture(org)

      {:ok, signed_firmware_path} =
        Fwup.create_signed_firmware(org_key.name, "unsigned", "signed", %{product: product.name})

      upload = %Plug.Upload{
        path: signed_firmware_path,
        filename: "doesnt_matter.fw"
      }

      # check for the error message
      conn =
        post(conn, Routes.firmware_path(conn, :upload, org.name, product.name), %{
          "firmware" => %{"file" => upload}
        })

      assert html_response(conn, 200) =~ "exceeds maximum size"
    end
  end

  describe "delete firmware" do
    test "deletes chosen firmware", %{
      conn: conn,
      user: user,
      org: org
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org)
      firmware = Fixtures.firmware_fixture(org_key, product)

      conn =
        delete(conn, Routes.firmware_path(conn, :delete, org.name, product.name, firmware.uuid))

      assert redirected_to(conn) == Routes.firmware_path(conn, :index, org.name, product.name)
      assert Firmwares.get_firmware(org, firmware.id) == {:error, :not_found}
    end

    test "error when firmware has associated deployments", %{
      conn: conn,
      user: user,
      org: org
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org)
      firmware = Fixtures.firmware_fixture(org_key, product)

      # Create a deployment from the firmware
      Fixtures.deployment_fixture(org, firmware)

      conn =
        delete(conn, Routes.firmware_path(conn, :delete, org.name, product.name, firmware.uuid))

      assert redirected_to(conn) == Routes.firmware_path(conn, :index, org.name, product.name)
      assert get_flash(conn, :error) =~ "Firmware has associated deployments"
    end
  end

  describe "download firmware" do
    test "downloads chosen firmware", %{
      conn: conn,
      user: user,
      org: org
    } do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org)
      firmware = Fixtures.firmware_fixture(org_key, product)

      conn =
        get(conn, Routes.firmware_path(conn, :download, org.name, product.name, firmware.uuid))

      assert redirected_to(conn) == firmware.upload_metadata.public_path
    end
  end
end
