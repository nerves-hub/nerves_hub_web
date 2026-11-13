defmodule NervesHub.Workers.CleanUpSoftDeletedDevicesTest do
  use NervesHub.DataCase

  alias NervesHub.Devices.Device
  alias NervesHub.Fixtures
  alias NervesHub.Products.Notification
  alias NervesHub.Workers.CleanUpSoftDeletedDevices

  test "cleans up soft deleted devices if enabled via the Application env", %{tmp_dir: tmp_dir} do
    Application.put_env(:nerves_hub, :clean_up_soft_deleted_devices, true)

    on_exit(fn ->
      Application.put_env(:nerves_hub, :clean_up_soft_deleted_devices, false)
    end)

    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

    _ = Fixtures.device_fixture(org, product, firmware)

    _ =
      Fixtures.device_fixture(org, product, firmware)
      |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-14, :day))
      |> Repo.update!()

    assert Repo.aggregate(Device, :count, :id) == 2

    assert :ok = perform_job(CleanUpSoftDeletedDevices, %{})

    assert Repo.aggregate(Device, :count, :id) == 1

    assert Repo.aggregate(Notification, :count, :id) == 1
  end

  test "cleans up a soft deleted device whose identifier contains spaces", %{tmp_dir: tmp_dir} do
    Application.put_env(:nerves_hub, :clean_up_soft_deleted_devices, true)

    on_exit(fn ->
      Application.put_env(:nerves_hub, :clean_up_soft_deleted_devices, false)
    end)

    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

    _ = soft_deleted_device_fixture(org, product, firmware, " leading space-0001")

    assert :ok = perform_job(CleanUpSoftDeletedDevices, %{})

    assert Repo.aggregate(Device, :count, :id) == 0

    assert [%Notification{event_key: "soft_deleted_device- leading space-0001"}] = Repo.all(Notification)
  end

  test "a device that cannot be cleaned up does not stop the others", %{tmp_dir: tmp_dir} do
    Application.put_env(:nerves_hub, :clean_up_soft_deleted_devices, true)

    on_exit(fn ->
      Application.put_env(:nerves_hub, :clean_up_soft_deleted_devices, false)
    end)

    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

    # Fits the identifier column, but its notification's event key doesn't, so
    # inserting the notification raises and the device's removal rolls back.
    stuck = soft_deleted_device_fixture(org, product, firmware, String.duplicate("a", 250))
    _ = soft_deleted_device_fixture(org, product, firmware, "removable-0001")

    assert :ok = perform_job(CleanUpSoftDeletedDevices, %{})

    assert [%Device{id: id}] = Repo.all(Device)
    assert id == stuck.id

    assert [%Notification{event_key: "soft_deleted_device-removable-0001"}] = Repo.all(Notification)
  end

  test "does not clean up soft deleted devices if disabled via the Application env", %{tmp_dir: tmp_dir} do
    Application.put_env(:nerves_hub, :clean_up_soft_deleted_devices, false)

    on_exit(fn ->
      Application.put_env(:nerves_hub, :clean_up_soft_deleted_devices, false)
    end)

    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

    _ = Fixtures.device_fixture(org, product, firmware)

    _ =
      Fixtures.device_fixture(org, product, firmware)
      |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-14, :day))
      |> Repo.update!()

    assert Repo.aggregate(Device, :count, :id) == 2

    assert :ok = perform_job(CleanUpSoftDeletedDevices, %{})

    assert Repo.aggregate(Device, :count, :id) == 2

    assert Repo.aggregate(Notification, :count, :id) == 0
  end

  defp soft_deleted_device_fixture(org, product, firmware, identifier) do
    org
    |> Fixtures.device_fixture(product, firmware, %{identifier: identifier})
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-14, :day))
    |> Repo.update!()
  end
end
