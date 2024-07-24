defmodule NervesHub.Workers.DeviceHealthTruncationTest do
  use NervesHub.DataCase

  alias NervesHub.Fixtures
  alias NervesHub.Devices
  alias NervesHub.Workers.DeviceHealthTruncation

  test "delete device health entries older than 7 days", %{tmp_dir: dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: dir})
    device = Fixtures.device_fixture(org, product, firmware)

    for x <- 0..9 do
      days_ago = DateTime.shift(DateTime.utc_now(), day: -x)

      inserted =
        %{"device_id" => device.id, "data" => %{"literally_any_map" => "values"}}
        |> Devices.DeviceHealth.save()
        |> Ecto.Changeset.put_change(:inserted_at, days_ago)
        |> Repo.insert()

      assert {:ok, %Devices.DeviceHealth{}} = inserted
    end

    assert :ok = perform_job(DeviceHealthTruncation, %{})

    healths = Devices.get_all_health(device.id)
    assert 7 = Enum.count(healths)
  end
end
