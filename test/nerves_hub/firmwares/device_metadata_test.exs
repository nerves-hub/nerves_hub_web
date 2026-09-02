defmodule NervesHub.Firmwares.DeviceMetadataTest do
  @moduledoc """
  Covers `Firmwares.metadata_from_device/2` reading more than one device dialect.

  The compatibility cases matter most: devices in the field cannot be upgraded,
  so a Nerves device reporting `nerves_fw_*` must keep resolving exactly as it
  did before the update tool seam existed.
  """
  use NervesHub.DataCase, async: true

  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.UpdateTool
  alias NervesHub.Fixtures
  alias NervesHub.Support.EspIdf

  @elf_sha256 String.duplicate("ab", 32)

  defp nerves_params(overrides \\ %{}) do
    Map.merge(
      %{
        "nerves_fw_uuid" => Ecto.UUID.generate(),
        "nerves_fw_product" => "my_product",
        "nerves_fw_version" => "1.2.3",
        "nerves_fw_platform" => "rpi4",
        "nerves_fw_architecture" => "arm",
        "nerves_fw_author" => "me",
        "nerves_fw_description" => "a description",
        "fwup_version" => "1.13.0",
        "nerves_fw_vcs_identifier" => "abc123",
        "nerves_fw_misc" => "misc"
      },
      overrides
    )
  end

  defp esp_params(overrides \\ %{}) do
    Map.merge(
      %{
        "esp_idf_project_name" => "my_product",
        "esp_idf_version" => "1.2.3",
        "esp_idf_app_elf_sha256" => @elf_sha256,
        "esp_idf_ver" => "v5.2.1",
        "esp_idf_chip_id" => 9
      },
      overrides
    )
  end

  describe "tool selection" do
    test "an explicit update_tool wins" do
      params = Map.put(esp_params(), "update_tool", "esp-idf")
      assert UpdateTool.for_device_metadata(params) == UpdateTool.EspIdf
    end

    test "an unknown update_tool falls back to sniffing" do
      params = Map.put(nerves_params(), "update_tool", "not-a-real-tool")
      assert UpdateTool.for_device_metadata(params) == UpdateTool.Fwup
    end

    test "nerves_fw_uuid identifies a Nerves device" do
      assert UpdateTool.for_device_metadata(nerves_params()) == UpdateTool.Fwup
    end

    test "esp_idf keys identify an ESP-IDF device" do
      assert UpdateTool.for_device_metadata(esp_params()) == UpdateTool.EspIdf
    end

    # Devices that report nothing recognisable must keep being read as fwup,
    # which is how every device was read before this seam existed.
    test "unrecognisable params fall back to fwup" do
      assert UpdateTool.for_device_metadata(%{"something" => "else"}) == UpdateTool.Fwup
    end
  end

  describe "metadata_from_device/2 with a Nerves device" do
    test "reads nerves_fw_* keys", %{} do
      product = product_fixture()
      params = nerves_params()

      assert {:ok, metadata} = Firmwares.metadata_from_device(params, product.id)

      assert metadata.uuid == params["nerves_fw_uuid"]
      assert metadata.product == "my_product"
      assert metadata.version == "1.2.3"
      assert metadata.platform == "rpi4"
      assert metadata.architecture == "arm"
      assert metadata.author == "me"
      assert metadata.fwup_version == "1.13.0"
      assert metadata.vcs_identifier == "abc123"
      assert metadata.misc == "misc"
    end

    test "falls back to a database lookup when the report is incomplete", %{} do
      %{firmware: firmware, product: product} = firmware_fixture()

      params = %{"nerves_fw_uuid" => firmware.uuid}

      assert {:ok, metadata} = Firmwares.metadata_from_device(params, product.id)
      assert metadata.uuid == firmware.uuid
      assert metadata.version == firmware.version
    end

    test "returns nil when nothing identifies the firmware" do
      product = product_fixture()
      assert {:ok, nil} = Firmwares.metadata_from_device(%{}, product.id)
    end
  end

  describe "metadata_from_device/2 with an ESP-IDF device" do
    test "reads esp_idf_* keys" do
      product = product_fixture()

      assert {:ok, metadata} = Firmwares.metadata_from_device(esp_params(), product.id)

      assert metadata.product == "my_product"
      assert metadata.version == "1.2.3"
      assert metadata.platform == "esp32s3"
      assert metadata.architecture == "xtensa"
      assert metadata.description == "ESP-IDF v5.2.1"
    end

    # The device sends the raw hash and the server derives the UUID, so a device
    # agent never has to know NervesHub's convention.
    test "derives the same uuid the uploaded image was given" do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.esp_idf_product_fixture(user, org)
      _esp_key = Fixtures.esp_idf_key_fixture(org, user)

      raw = :crypto.strong_rand_bytes(32)

      {:ok, path} =
        EspIdf.create_firmware(product.name, elf_sha256: raw)

      {:ok, firmware} = Firmwares.create_firmware(org, path)

      params = esp_params(%{"esp_idf_app_elf_sha256" => Base.encode16(raw, case: :lower)})

      assert {:ok, metadata} = Firmwares.metadata_from_device(params, product.id)
      assert metadata.uuid == firmware.uuid
    end

    test "accepts a chip id sent as a string" do
      product = product_fixture()
      params = esp_params(%{"esp_idf_chip_id" => "13"})

      assert {:ok, metadata} = Firmwares.metadata_from_device(params, product.id)
      assert metadata.platform == "esp32c6"
      assert metadata.architecture == "riscv"
    end

    test "normalises a non-semver PROJECT_VER rather than failing" do
      product = product_fixture()
      params = esp_params(%{"esp_idf_version" => "v2.1"})

      assert {:ok, metadata} = Firmwares.metadata_from_device(params, product.id)
      assert metadata.version == "2.1.0"
    end

    test "survives a malformed elf hash" do
      product = product_fixture()
      params = esp_params(%{"esp_idf_app_elf_sha256" => "not-hex"})

      assert {:ok, nil} = Firmwares.metadata_from_device(params, product.id)
    end
  end

  defp product_fixture() do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    Fixtures.product_fixture(user, org)
  end

  defp firmware_fixture() do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)

    %{firmware: firmware, product: product}
  end
end
