defmodule NervesHub.Ash.Firmwares.FirmwareTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Ash.Firmwares.Firmware
  alias NervesHub.Fixtures

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

    %{user: user, org: org, product: product, org_key: org_key, firmware: firmware}
  end

  describe "read" do
    test "get by id", %{firmware: firmware} do
      found = Firmware.get!(firmware.id)
      assert found.id == firmware.id
      assert found.uuid == firmware.uuid
    end

    test "list_by_product returns firmwares", %{product: product, firmware: firmware} do
      firmwares = Firmware.list_by_product!(product.id)
      assert Enum.any?(firmwares, &(&1.id == firmware.id))
    end

    test "list_by_org returns firmwares", %{org: org, firmware: firmware} do
      firmwares = Firmware.list_by_org!(org.id)
      assert Enum.any?(firmwares, &(&1.id == firmware.id))
    end

    test "get_by_product_and_uuid returns firmware", %{product: product, firmware: firmware} do
      found = Firmware.get_by_product_and_uuid!(product.id, firmware.uuid)
      assert found.id == firmware.id
    end
  end

  describe "get_by_platform_and_architecture" do
    test "returns firmwares matching platform and architecture", %{product: product, firmware: firmware} do
      ecto_fw = NervesHub.Repo.get!(NervesHub.Firmwares.Firmware, firmware.id)
      results = Firmware.get_by_platform_and_architecture!(product.id, ecto_fw.platform, ecto_fw.architecture)
      assert Enum.any?(results, &(&1.id == firmware.id))
    end
  end

  describe "count_by_product" do
    test "returns firmware count for product", %{product: product} do
      count = Firmware.count_by_product!(product.id)
      assert is_integer(count)
      assert count >= 1
    end
  end

  describe "unique_platforms" do
    test "returns unique platforms for product", %{product: product} do
      platforms = Firmware.unique_platforms!(product.id)
      assert is_list(platforms)
      assert length(platforms) >= 1
    end
  end

  describe "unique_architectures" do
    test "returns unique architectures for product", %{product: product} do
      architectures = Firmware.unique_architectures!(product.id)
      assert is_list(architectures)
      assert length(architectures) >= 1
    end
  end

  describe "versions_by_product" do
    test "returns firmware versions for product", %{product: product} do
      versions = Firmware.versions_by_product!(product.id)
      assert is_list(versions)
      assert length(versions) >= 1
    end
  end

  describe "get_for_device" do
    test "returns firmwares matching device attributes", %{org: org, product: product, firmware: firmware} do
      ecto_fw = NervesHub.Repo.get!(NervesHub.Firmwares.Firmware, firmware.id)
      results = Firmware.get_for_device!(ecto_fw.platform, ecto_fw.architecture, org.id, product.id)
      assert Enum.any?(results, &(&1.id == firmware.id))
    end
  end

  describe "destroy" do
    test "soft-deletes firmware", %{firmware: firmware} do
      ash_firmware = Firmware.get!(firmware.id)
      assert :ok = Firmware.destroy!(ash_firmware)
    end
  end
end
