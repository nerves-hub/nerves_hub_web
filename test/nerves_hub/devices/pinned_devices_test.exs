defmodule NervesHub.Devices.PinnedDevicesTest do
  alias NervesHub.Accounts
  use NervesHub.DataCase, async: false

  alias NervesHub.Fixtures
  alias NervesHub.Devices
  alias NervesHub.Devices.PinnedDevice

  setup do
    user = Fixtures.user_fixture()
    user2 = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    org2 = Fixtures.org_fixture(user2, name: "org2")
    product = Fixtures.product_fixture(user, org)
    product2 = Fixtures.product_fixture(user2, org2, name: "Product2")
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    device = Fixtures.device_fixture(org, product, firmware)

    {:ok,
     %{
       device: device,
       user: user,
       user2: user2,
       org: org,
       org2: org2,
       product: product,
       product2: product2
     }}
  end

  test "Pin device", %{device: device, user: user} do
    assert {:ok, pinned} =
             Devices.pin_device(user.id, device.id)

    assert pinned.device_id == device.id
    assert pinned.user_id == user.id
  end

  test "Constraint on device and user", %{device: device, user: user} do
    assert {:error, _changeset} =
             Devices.pin_device(user.id, 17)

    assert {:error, _changeset} =
             Devices.pin_device(2, device.id)
  end

  test "Get pinned devices for user", %{user: user, device: device} do
    {:ok, _} =
      Devices.pin_device(user.id, device.id)

    devices = Devices.get_pinned_devices(user.id)
    assert length(devices) == 1
  end

  test "Unpin device", %{device: device, user: user} do
    assert {:ok, _} =
             Devices.pin_device(user.id, device.id)

    {:ok, %PinnedDevice{}} = Devices.unpin_device(user.id, device.id)
  end

  test "Move device to new org - unpin if user has no access to new org", %{
    user: user,
    device: device,
    product2: product2
  } do
    assert {:ok, _} =
             Devices.pin_device(user.id, device.id)

    pinned_devices = Devices.get_pinned_devices(user.id)
    assert length(pinned_devices) == 1

    # Move device to product2, which belongs to other org
    Devices.move(device, product2, user)

    # Assert device is unpinned for unauthorized user
    assert [] == Devices.get_pinned_devices(user.id)
  end

  test "Unpin devices when org access for user is revoked", %{
    user2: user2,
    device: device,
    org: org
  } do
    # Add user2 to org
    Accounts.add_org_user(org, user2, %{role: :view})

    assert {:ok, _} =
             Devices.pin_device(user2.id, device.id)

    pinned_devices = Devices.get_pinned_devices(user2.id)
    assert length(pinned_devices) == 1

    # Remove org access for user
    :ok = Accounts.remove_org_user(org, user2)

    # Assert user has no pinned devices
    assert [] = Devices.get_pinned_devices(user2.id)
  end

  test "Remove entries when user is soft-deleted", %{user: user, device: device} do
    assert {:ok, _} =
             Devices.pin_device(user.id, device.id)

    pinned_devices = Devices.get_pinned_devices(user.id)
    assert length(pinned_devices) == 1

    # Soft Delete user
    Accounts.remove_account(user.id)
    assert [] = Devices.get_pinned_devices(user.id)
  end

  test "Remove entries when device is (soft)deleted", %{user: user, device: device} do
    assert {:ok, _} =
             Devices.pin_device(user.id, device.id)

    Devices.delete_device(device)
    assert [] = Devices.get_pinned_devices(user.id)
  end
end
