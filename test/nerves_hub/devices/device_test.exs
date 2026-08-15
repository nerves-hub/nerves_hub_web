defmodule NervesHub.Devices.DeviceTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Devices.Device
  alias NervesHub.Fixtures

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)
    %{org: org, product: product, device: device}
  end

  test "changeset/2 adds error when updating a soft-deleted device", %{org: org, product: product, device: device} do
    deleted_device = %{device | deleted_at: DateTime.utc_now()}
    changeset = Device.changeset(deleted_device, %{description: "new description"})
    assert {:deleted_at, {"cannot update while marked as deleted", []}} in changeset.errors
  end

  test "changeset/2 allows updating deleted_at on a soft-deleted device", %{device: device} do
    deleted_device = %{device | deleted_at: DateTime.utc_now()}
    changeset = Device.changeset(deleted_device, %{deleted_at: nil})
    refute Keyword.has_key?(changeset.errors, :deleted_at)
  end
end
