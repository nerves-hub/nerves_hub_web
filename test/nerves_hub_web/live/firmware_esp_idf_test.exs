defmodule NervesHubWeb.Live.FirmwareEspIdfTest do
  @moduledoc """
  Covers ESP-IDF firmware in the web UI.
  """
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Firmwares
  alias NervesHub.Fixtures
  alias NervesHub.Support.EspIdf

  defp upload_esp_idf!(org, product, opts \\ []) do
    {:ok, path} = EspIdf.create_firmware(product.name, opts)
    {:ok, firmware} = Firmwares.create_firmware(org, path, product: product)
    firmware
  end

  describe "index" do
    test "lists an ESP-IDF firmware alongside its tool", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      _key = Fixtures.esp_idf_key_fixture(org, user)
      firmware = upload_esp_idf!(org, product, version: "1.4.0", chip_id: 0x0009)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("a", text: firmware.uuid)
      |> assert_has("code", text: "esp-idf")
      |> assert_has("td", text: "esp32s3")
      |> assert_has("td", text: "xtensa")
    end

    test "shows the key that signed it", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      key = Fixtures.esp_idf_key_fixture(org, user)
      firmware = upload_esp_idf!(org, product)

      assert firmware.org_key_id == key.id

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("code", text: key.name)
    end

    test "shows fwup and ESP-IDF firmware side by side", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      _esp_key = Fixtures.esp_idf_key_fixture(org, user)
      fwup_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      esp_firmware = upload_esp_idf!(org, product)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("a", text: fwup_firmware.uuid)
      |> assert_has("a", text: esp_firmware.uuid)
      |> assert_has("code", text: "esp-idf")
      |> assert_has("code", text: "fwup")
    end
  end

  describe "show" do
    test "renders the ESP-IDF metadata", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      _key = Fixtures.esp_idf_key_fixture(org, user)
      firmware = upload_esp_idf!(org, product, version: "2.1.0", chip_id: 0x000D)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> assert_has("h1", text: firmware.uuid)
      |> assert_has("span", text: "2.1.0")
      |> assert_has("code", text: "esp-idf")
      |> assert_has("span", text: "esp32c6")
      |> assert_has("span", text: "riscv")
      |> assert_has("span", text: "ESP-IDF v5.2.1")
    end

    test "renders the signing key on the show page", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      key = Fixtures.esp_idf_key_fixture(org, user)
      firmware = upload_esp_idf!(org, product)

      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}")
      |> assert_has("code", text: key.name)
    end
  end

  describe "upload" do
    test "the file picker accepts ESP-IDF images", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)

      # `accept` reaches the browser as the input's accept attribute, so this is
      # the only place a client-side rejection of .bin would show up.
      conn
      |> visit("/org/#{org.name}/#{product.name}/firmware")
      |> assert_has("input[type='file'][accept*='.bin']")
      |> assert_has("input[type='file'][accept*='.fw']")
    end
  end
end
