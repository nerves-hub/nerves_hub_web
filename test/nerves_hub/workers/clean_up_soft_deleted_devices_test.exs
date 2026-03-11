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
end
