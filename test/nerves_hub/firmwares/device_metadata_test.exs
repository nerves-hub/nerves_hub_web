defmodule NervesHub.Firmwares.DeviceMetadataTest do
  @moduledoc """
  Covers `Firmwares.metadata_from_device/2` resolving a device's dialect.

  The compatibility cases matter most: devices in the field cannot be upgraded,
  so a Nerves device reporting `nerves_fw_*` must keep resolving exactly as it
  did before this seam existed.
  """
  use NervesHub.DataCase, async: true

  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.UpdateTool
  alias NervesHub.Fixtures

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

  describe "tool selection" do
    test "an explicit update_tool wins" do
      params = Map.put(nerves_params(), "update_tool", "fwup")
      assert UpdateTool.for_device_metadata(params) == UpdateTool.Fwup
    end

    test "an unknown update_tool falls back to sniffing" do
      params = Map.put(nerves_params(), "update_tool", "not-a-real-tool")
      assert UpdateTool.for_device_metadata(params) == UpdateTool.Fwup
    end

    test "nerves_fw_uuid identifies a Nerves device" do
      assert UpdateTool.for_device_metadata(nerves_params()) == UpdateTool.Fwup
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
