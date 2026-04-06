defmodule NervesHub.Ash.Devices.DeviceTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Ash.Devices.Device
  alias NervesHub.Fixtures

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    %{user: user, org: org, product: product, org_key: org_key, firmware: firmware, device: device}
  end

  describe "read" do
    test "get by id", %{device: device} do
      found = Device.get!(device.id)
      assert found.id == device.id
      assert found.identifier == device.identifier
    end

    test "list_by_product returns devices", %{org: org, product: product, device: device} do
      devices = Device.list_by_product!(org.id, product.id)
      assert Enum.any?(devices, &(&1.id == device.id))
    end

    test "get_by_identifier returns device", %{device: device} do
      found = Device.get_by_identifier!(device.identifier)
      assert found.id == device.id
    end

    test "get_by_identifier excludes soft-deleted devices", %{device: device} do
      NervesHub.Devices.delete_device(
        NervesHub.Repo.get!(NervesHub.Devices.Device, device.id)
      )

      assert {:error, _} = Device.get_by_identifier(device.identifier)
    end
  end

  describe "create" do
    test "creates device", %{org: org, product: product} do
      device =
        Device.create!(%{
          identifier: "ash-device-#{System.unique_integer([:positive])}",
          org_id: org.id,
          product_id: product.id
        })

      assert device.id
      assert device.status == :registered
    end
  end

  describe "update" do
    test "updates device description", %{device: device} do
      ash_device = Device.get!(device.id)
      updated = Device.update!(ash_device, %{description: "Updated description"})
      assert updated.description == "Updated description"
    end
  end

  describe "move" do
    test "moves device to different product", %{user: user, org: org, device: device} do
      product2 = Fixtures.product_fixture(user, org, %{name: "product2"})
      ash_device = Device.get!(device.id)

      moved = Device.move!(ash_device, product2.id, user.id)
      assert moved.product_id == product2.id
    end
  end

  describe "enable_updates / disable_updates" do
    test "toggles updates", %{user: user, device: device} do
      ash_device = Device.get!(device.id)

      disabled = Device.disable_updates!(ash_device, user.id)
      assert disabled.updates_enabled == false

      enabled = Device.enable_updates!(disabled, user.id)
      assert enabled.updates_enabled == true
    end
  end

  describe "tag" do
    test "sets tags on device", %{device: device} do
      ash_device = Device.get!(device.id)

      tagged = Device.tag!(ash_device, ["prod", "us-east"])
      assert tagged.tags == ["prod", "us-east"]
    end
  end

  describe "restore" do
    test "restores soft-deleted device", %{device: device} do
      NervesHub.Devices.delete_device(
        NervesHub.Repo.get!(NervesHub.Devices.Device, device.id)
      )

      # Get the device directly (bypassing soft-delete filter)
      ash_device = Device.get!(device.id)
      assert ash_device.deleted_at != nil

      restored = Device.restore!(ash_device)
      assert restored.deleted_at == nil
    end
  end

  describe "destroy" do
    test "soft-deletes device", %{device: device} do
      ash_device = Device.get!(device.id)
      assert :ok = Device.destroy!(ash_device)

      ecto_device = NervesHub.Repo.get(NervesHub.Devices.Device, device.id)
      assert ecto_device.deleted_at != nil
    end
  end

  describe "hard_destroy" do
    test "permanently deletes device", %{device: device} do
      ash_device = Device.get!(device.id)
      assert :ok = Device.hard_destroy!(ash_device)

      assert NervesHub.Repo.get(NervesHub.Devices.Device, device.id) == nil
    end
  end

  describe "set_as_provisioned" do
    test "marks device as provisioned", %{device: device} do
      ash_device = Device.get!(device.id)
      provisioned = Device.set_as_provisioned!(ash_device)
      assert provisioned.status == :provisioned
    end
  end

  describe "enable_extension / disable_extension" do
    test "manages device extensions", %{device: device} do
      ash_device = Device.get!(device.id)

      enabled = Device.enable_extension!(ash_device, "geo")
      assert enabled.extensions["geo"] == true

      disabled = Device.disable_extension!(enabled, "geo")
      assert disabled.extensions["geo"] == false
    end
  end

  describe "get_by_org" do
    test "returns device scoped to org", %{org: org, device: device} do
      found = Device.get_by_org!(org.id, device.id)
      assert found.id == device.id
    end

    test "excludes soft-deleted devices", %{org: org, device: device} do
      NervesHub.Devices.delete_device(
        NervesHub.Repo.get!(NervesHub.Devices.Device, device.id)
      )

      assert {:error, _} = Device.get_by_org(org.id, device.id)
    end
  end

  describe "list_by_org" do
    test "returns devices for org", %{org: org, device: device} do
      devices = Device.list_by_org!(org.id)
      assert Enum.any?(devices, &(&1.id == device.id))
    end

    test "excludes soft-deleted devices", %{org: org, device: device} do
      NervesHub.Devices.delete_device(
        NervesHub.Repo.get!(NervesHub.Devices.Device, device.id)
      )

      devices = Device.list_by_org!(org.id)
      refute Enum.any?(devices, &(&1.id == device.id))
    end
  end

  describe "count_by_org" do
    test "returns count of devices in org", %{org: org} do
      count = Device.count_by_org!(org.id)
      assert is_integer(count)
      assert count >= 1
    end
  end

  describe "count_by_product" do
    test "returns count of devices for product", %{product: product} do
      count = Device.count_by_product!(product.id)
      assert is_integer(count)
      assert count >= 1
    end
  end

  describe "count_by_org_and_product" do
    test "returns count of devices for org and product", %{org: org, product: product} do
      count = Device.count_by_org_and_product!(org.id, product.id)
      assert is_integer(count)
      assert count >= 1
    end
  end

  describe "in_penalty_box" do
    test "returns false for device not in penalty box", %{device: device} do
      result = Device.in_penalty_box!(device.id)
      assert result == false
    end
  end

  describe "has_certificates" do
    test "returns boolean for device certificates check", %{device: device} do
      result = Device.has_certificates!(device.id)
      assert is_boolean(result)
    end
  end

  describe "toggle_updates" do
    test "toggles updates enabled state", %{user: user, device: device} do
      ash_device = Device.get!(device.id)
      assert ash_device.updates_enabled == true

      toggled = Device.toggle_updates!(ash_device, user.id)
      assert toggled.updates_enabled == false

      toggled_back = Device.toggle_updates!(toggled, user.id)
      assert toggled_back.updates_enabled == true
    end
  end

  describe "firmware_validated" do
    test "marks firmware as validated", %{device: device} do
      ash_device = Device.get!(device.id)
      validated = Device.firmware_validated!(ash_device)
      assert validated.firmware_validation_status == :validated
    end
  end

  describe "soft_deleted_exist_for_product" do
    test "returns false when no soft-deleted devices", %{product: product} do
      assert Device.soft_deleted_exist_for_product!(product.id) == false
    end

    test "returns true when soft-deleted devices exist", %{product: product, device: device} do
      NervesHub.Devices.delete_device(
        NervesHub.Repo.get!(NervesHub.Devices.Device, device.id)
      )

      assert Device.soft_deleted_exist_for_product!(product.id) == true
    end
  end
end
