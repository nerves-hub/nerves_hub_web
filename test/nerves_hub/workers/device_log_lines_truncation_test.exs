defmodule NervesHub.Workers.DeviceLogLinesTruncationTest do
  use NervesHub.DataCase

  alias NervesHub.Devices.LogLines
  alias NervesHub.Fixtures
  alias NervesHub.Workers.DeviceLogLinesTruncation

  test "delete device log lines older than 3 days", %{tmp_dir: dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: dir})
    device = Fixtures.device_fixture(org, product, firmware)

    # Insert log lines, from 5 days ago until today
    for x <- 5..1//-1 do
      days_ago =
        DateTime.utc_now()
        |> DateTime.shift(day: -x)
        |> DateTime.shift(minute: 2)

      attrs = %{
        level: :info,
        logged_at: days_ago,
        message: "a few days ago"
      }

      LogLines.create!(device, attrs)
    end

    log_lines = LogLines.recent(device)
    assert 5 = Enum.count(log_lines)

    assert :ok = perform_job(DeviceLogLinesTruncation, %{})

    log_lines = LogLines.recent(device)
    assert 3 = Enum.count(log_lines)
  end
end
