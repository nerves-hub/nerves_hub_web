defmodule NervesHub.Firmwares.ProductUpdateToolSettingsTest do
  @moduledoc """
  Per-product control over which firmware formats are accepted, and whether an
  unsigned ESP-IDF image is allowed.
  """
  use NervesHub.DataCase, async: true

  alias NervesHub.Firmwares
  alias NervesHub.Fixtures
  alias NervesHub.Products
  alias NervesHub.Products.Product
  alias NervesHub.Support.EspIdf
  alias NervesHub.Support.Fwup

  @moduletag :tmp_dir

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)

    {:ok, %{user: user, org: org}}
  end

  defp upload(org, product, opts \\ []) do
    {:ok, path} = EspIdf.create_firmware(product.name, opts)
    Firmwares.create_firmware(org, path, product: product)
  end

  describe "allowed_update_tools" do
    test "defaults to fwup only", %{user: user, org: org} do
      product = Fixtures.product_fixture(user, org)

      assert product.allowed_update_tools == ["fwup"]
      assert Product.accepts_update_tool?(product, "fwup")
      refute Product.accepts_update_tool?(product, "esp-idf")
    end

    # The whole point: a product does not start accepting a new format because
    # the platform gained support for one.
    test "an esp-idf upload is refused by a default product", %{user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      _key = Fixtures.esp_idf_key_fixture(org, user)

      assert {:error, {:update_tool_not_allowed, "esp-idf", name}} = upload(org, product)
      assert name == product.name
    end

    test "an esp-idf upload succeeds once the product opts in", %{user: user, org: org} do
      product = Fixtures.esp_idf_product_fixture(user, org)
      key = Fixtures.esp_idf_key_fixture(org, user)

      assert {:ok, firmware} = upload(org, product)
      assert firmware.tool == "esp-idf"
      assert firmware.org_key_id == key.id
    end

    test "fwup keeps working on an esp-idf product", %{user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.esp_idf_product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      assert %{tool: "fwup"} = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    end

    test "an unknown tool is rejected at the changeset", %{user: user, org: org} do
      product = Fixtures.product_fixture(user, org)

      assert {:error, changeset} =
               Products.update_product(product, %{allowed_update_tools: ["fwup", "wat"]})

      assert "unknown update tool(s): wat" in errors_on(changeset).allowed_update_tools
    end
  end

  describe "allow_unsigned_esp_idf_firmware" do
    test "defaults to false, so an unsigned image is refused", %{user: user, org: org} do
      product = Fixtures.esp_idf_product_fixture(user, org)

      refute product.allow_unsigned_esp_idf_firmware
      assert {:error, :firmware_not_signed} = upload(org, product, signed: false)
    end

    test "allows an unsigned image when set", %{user: user, org: org} do
      product =
        Fixtures.esp_idf_product_fixture(user, org, %{allow_unsigned_esp_idf_firmware: true})

      assert {:ok, firmware} = upload(org, product, signed: false)
      assert firmware.tool == "esp-idf"
      assert is_nil(firmware.org_key_id)
    end

    # The setting excuses a *missing* signature, never a bad one — otherwise it
    # would quietly accept an image signed by a key nobody registered.
    test "still refuses an image signed by an unregistered key", %{user: user, org: org} do
      product =
        Fixtures.esp_idf_product_fixture(user, org, %{allow_unsigned_esp_idf_firmware: true})

      # Signed, but the org registered no matching key.
      assert {:error, :invalid_signature} = upload(org, product)
    end

    # fwup is verified by fwup itself; no product setting reaches that path.
    test "does not weaken fwup", %{user: user, org: org, tmp_dir: tmp_dir} do
      product =
        Fixtures.esp_idf_product_fixture(user, org, %{allow_unsigned_esp_idf_firmware: true})

      :ok = Fwup.gen_key_pair("unregistered", tmp_dir)

      {:ok, path} =
        Fwup.create_signed_firmware("unregistered", "unsigned", "signed", %{
          product: product.name,
          dir: tmp_dir
        })

      assert {:error, :no_public_keys} = Firmwares.create_firmware(org, path, product: product)
    end
  end
end
