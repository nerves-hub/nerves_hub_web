defmodule NervesHub.Devices.PinnedDeviceTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Devices.PinnedDevice
  alias NervesHub.Fixtures

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    device = Fixtures.device_fixture(org, product, firmware)

    %{user: user, device: device}
  end

  describe "create/1" do
    test "valid params produce a valid changeset", %{user: user, device: device} do
      changeset = PinnedDevice.create(%{user_id: user.id, device_id: device.id})
      assert changeset.valid?
    end

    test "missing user_id is invalid" do
      changeset = PinnedDevice.create(%{device_id: 1})
      refute changeset.valid?
      assert changeset.errors[:user_id]
    end

    test "missing device_id is invalid" do
      changeset = PinnedDevice.create(%{user_id: 1})
      refute changeset.valid?
      assert changeset.errors[:device_id]
    end

    test "empty params are invalid" do
      changeset = PinnedDevice.create(%{})
      refute changeset.valid?
      assert changeset.errors[:user_id]
      assert changeset.errors[:device_id]
    end

    test "invalid user_id foreign key constraint fires on insert", %{device: device} do
      changeset = PinnedDevice.create(%{user_id: 0, device_id: device.id})

      assert {:error, cs} = NervesHub.Repo.insert(changeset)
      assert cs.errors[:user_id]
    end

    test "invalid device_id foreign key constraint fires on insert", %{user: user} do
      changeset = PinnedDevice.create(%{user_id: user.id, device_id: 0})

      assert {:error, cs} = NervesHub.Repo.insert(changeset)
      assert cs.errors[:device_id]
    end
  end
end
