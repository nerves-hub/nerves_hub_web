defmodule NervesHubWWWWeb.FirmwareControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: true

  alias NervesHubCore.Fixtures
  alias NervesHubCore.Accounts
  alias NervesHubCore.Support.Fwup

  describe "index" do
    test "lists all firmwares", %{conn: conn, current_org: org} do
      product = Fixtures.product_fixture(org)

      conn = get(conn, product_firmware_path(conn, :index, product.id))
      assert html_response(conn, 200) =~ "Firmware"
      assert html_response(conn, 200) =~ product_firmware_path(conn, :upload, product.id)
    end
  end

  describe "upload firmware form" do
    test "renders form with valid request params", %{conn: conn, current_org: org} do
      product = Fixtures.product_fixture(org)
      conn = get(conn, product_firmware_path(conn, :upload, product.id))

      assert html_response(conn, 200) =~ "Upload Firmware"
      assert html_response(conn, 200) =~ product_firmware_path(conn, :do_upload, product.id)
    end
  end

  describe "upload firmware" do
    test "redirects after successful upload", %{
      conn: conn,
      current_org: org,
      org_key: org_key
    } do
      product_name = "cool product"
      product = Fixtures.product_fixture(org, %{name: product_name})

      {:ok, signed_firmware_path} =
        Fwup.create_signed_firmware(org_key.name, "unsigned", "signed", %{product: product_name})

      upload = %Plug.Upload{
        path: signed_firmware_path,
        filename: "doesnt_matter.fw"
      }

      # check that we end up in the right place
      create_conn =
        post(conn, product_firmware_path(conn, :upload, product.id), %{
          "firmware" => %{"file" => upload}
        })

      assert redirected_to(create_conn, 302) =~ product_firmware_path(conn, :index, product.id)

      # check that the proper creation side effects took place
      conn = get(conn, product_firmware_path(conn, :index, product.id))
      # starter is the product for the test firmware
      assert html_response(conn, 200) =~ product_name
    end

    test "error if corrupt firmware uploaded", %{conn: conn, current_org: org, org_key: org_key} do
      product = Fixtures.product_fixture(org, %{name: "starter"})

      {:ok, signed_firmware_path} =
        Fwup.create_signed_firmware(org_key.name, "unsigned", "signed", %{product: "starter"})

      {:ok, corrupt_firmware_path} = Fwup.corrupt_firmware_file(signed_firmware_path)

      upload = %Plug.Upload{
        path: corrupt_firmware_path,
        filename: "doesnt_matter.fw"
      }

      # check for the error message
      conn =
        post(conn, product_firmware_path(conn, :upload, product.id), %{
          "firmware" => %{"file" => upload}
        })

      assert html_response(conn, 200) =~
               "Firmware corrupt, signature invalid or missing public key"
    end

    test "error if org keys do not match firmware", %{conn: conn, current_org: org} do
      product = Fixtures.product_fixture(org, %{name: "starter"})

      Fwup.gen_key_pair("wrong")

      {:ok, signed_firmware_path} =
        Fwup.create_signed_firmware("wrong", "unsigned", "signed", %{product: "starter"})

      upload = %Plug.Upload{
        path: signed_firmware_path,
        filename: "doesnt_matter.fw"
      }

      # check for the error message
      conn =
        post(conn, product_firmware_path(conn, :upload, product.id), %{
          "firmware" => %{"file" => upload}
        })

      assert html_response(conn, 200) =~
               "Firmware corrupt, signature invalid or missing public key"
    end

    test "error if meta-product does not match product name", %{
      conn: conn,
      current_org: org,
      org_key: org_key
    } do
      product = Fixtures.product_fixture(org, %{name: "non-matching name"})

      {:ok, signed_firmware_path} =
        Fwup.create_signed_firmware(org_key.name, "unsigned", "signed", %{product: "name"})

      upload = %Plug.Upload{
        path: signed_firmware_path,
        filename: "doesnt_matter.fw"
      }

      # check for the error message
      conn =
        post(conn, product_firmware_path(conn, :upload, product.id), %{
          "firmware" => %{"file" => upload}
        })

      assert html_response(conn, 200) =~ "No matching product could be found."
    end

    test "error if firmware size exceeds limit", %{
      conn: conn,
      current_org: org
    } do
      Accounts.create_org_limit(%{org_id: org.id, firmware_size: 1})
      product = Fixtures.product_fixture(org, %{name: "starter"})

      org_key = Fixtures.org_key_fixture(org)

      {:ok, signed_firmware_path} =
        Fwup.create_signed_firmware(org_key.name, "unsigned", "signed", %{product: product.name})

      upload = %Plug.Upload{
        path: signed_firmware_path,
        filename: "doesnt_matter.fw"
      }

      # check for the error message
      conn =
        post(conn, product_firmware_path(conn, :upload, product.id), %{
          "firmware" => %{"file" => upload}
        })

      assert html_response(conn, 200) =~ "exceeds maximum size"
    end
  end
end
