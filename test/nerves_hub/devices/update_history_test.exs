defmodule NervesHub.Devices.UpdateHistoryTest do
  # Not async: these tests read and write the AnalyticsRepo (ClickHouse), which
  # does not support concurrent writes.
  use NervesHub.DataCase, async: false
  use AssertEventually, timeout: 2000, interval: 50

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices
  alias NervesHub.Devices.DeviceUpdateHistory
  alias NervesHub.Devices.UpdateHistory
  alias NervesHub.Fixtures

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    AnalyticsRepo.query!("TRUNCATE TABLE device_update_history")

    on_exit(fn -> AnalyticsRepo.query!("TRUNCATE TABLE device_update_history") end)

    %{user: user, org: org, product: product, firmware: firmware, device: device}
  end

  defp history_for(device) do
    :ok = Buffer.flush(DeviceUpdateHistory)

    DeviceUpdateHistory
    |> AnalyticsRepo.all()
    |> Enum.filter(&(&1.device_id == device.id))
  end

  defp reload(device), do: Devices.get_device(device.id)

  describe "record/3" do
    test "writes a history row carrying the deployment, firmware and reason", %{
      device: device,
      product: product,
      org: org
    } do
      :ok =
        UpdateHistory.record(device, :failed,
          deployment_id: 42,
          source_firmware_uuid: "aaaaaaaa-0000-0000-0000-000000000000",
          target_firmware_uuid: "bbbbbbbb-0000-0000-0000-000000000000",
          reason: "fwup error"
        )

      assert_eventually([%DeviceUpdateHistory{} = row] = history_for(device))

      assert row.org_id == org.id
      assert row.product_id == product.id
      assert row.device_id == device.id
      assert row.deployment_id == 42
      assert row.status == "failed"
      assert row.source_firmware_uuid == "aaaaaaaa-0000-0000-0000-000000000000"
      assert row.target_firmware_uuid == "bbbbbbbb-0000-0000-0000-000000000000"
      assert row.reason == "fwup error"
    end

    test "records an absent deployment as 0 rather than failing on a null", %{device: device} do
      :ok = UpdateHistory.record(device, :abandoned)

      assert_eventually([row] = history_for(device))

      assert row.deployment_id == 0
      assert row.source_firmware_uuid == ""
      assert row.target_firmware_uuid == ""
      assert row.reason == ""
    end

    test "truncates a device supplied reason", %{device: device} do
      :ok = UpdateHistory.record(device, :ignored, reason: String.duplicate("x", 500))

      assert_eventually([row] = history_for(device))

      assert String.length(row.reason) == 200
    end

    test "records a timestamp given at second precision", %{device: device} do
      # `DateTime64(6)` refuses anything coarser than microseconds, and a
      # rejected row fails the whole buffer batch rather than only itself.
      at = DateTime.new!(~D[2026-02-03], ~T[04:05:06], "Etc/UTC")

      :ok = UpdateHistory.record(device, :expired, timestamp: at)

      assert_eventually([row] = history_for(device))

      assert DateTime.compare(row.timestamp, at) == :eq
    end

    test "every status is recordable", %{device: device} do
      for status <- UpdateHistory.statuses() do
        :ok = UpdateHistory.record(device, status)
      end

      expected = Enum.map(UpdateHistory.statuses(), &Atom.to_string/1)

      assert_eventually(Enum.sort(Enum.map(history_for(device), & &1.status)) == Enum.sort(expected))
    end
  end

  describe "the consecutive failure counter" do
    test "starts at zero", %{device: device} do
      assert device.consecutive_failed_updates == 0
      assert is_nil(device.last_update_failure_at)
    end

    test "moves on for each failure status", %{device: device} do
      for status <- UpdateHistory.failure_statuses() do
        :ok = UpdateHistory.record(device, status)
      end

      device = reload(device)

      assert device.consecutive_failed_updates == length(UpdateHistory.failure_statuses())
      refute is_nil(device.last_update_failure_at)
    end

    test "is not moved by a reschedule, which is a deferral rather than a failure", %{device: device} do
      :ok = UpdateHistory.record(device, :failed)
      :ok = UpdateHistory.record(device, :rescheduled)
      :ok = UpdateHistory.record(device, :rescheduled)

      assert reload(device).consecutive_failed_updates == 1
    end

    test "is cleared by a success, along with both failure times", %{device: device} do
      :ok = UpdateHistory.record(device, :failed)
      :ok = UpdateHistory.record(device, :expired)

      assert reload(device).consecutive_failed_updates == 2

      :ok = UpdateHistory.record(device, :succeeded)

      device = reload(device)

      assert device.consecutive_failed_updates == 0
      assert is_nil(device.first_update_failure_at)
      assert is_nil(device.last_update_failure_at)
    end

    test "remembers when the run of failures started, not just the latest one", %{device: device} do
      # truncated, because the column is second precision and the write floors it
      started = DateTime.utc_now() |> DateTime.add(-3, :day) |> DateTime.truncate(:second)

      :ok = UpdateHistory.record(device, :failed, timestamp: started)
      :ok = UpdateHistory.record(device, :expired)
      :ok = UpdateHistory.record(device, :abandoned)

      device = reload(device)

      assert device.consecutive_failed_updates == 3
      # the first failure pins the start; the later ones only move the end
      assert DateTime.diff(device.first_update_failure_at, started, :second) == 0
      assert DateTime.after?(device.last_update_failure_at, device.first_update_failure_at)
    end

    test "starts a fresh run after a success", %{device: device} do
      :ok = UpdateHistory.record(device, :failed, timestamp: DateTime.add(DateTime.utc_now(), -3, :day))
      :ok = UpdateHistory.record(device, :succeeded)

      recent = DateTime.utc_now() |> DateTime.add(-1, :hour) |> DateTime.truncate(:second)
      :ok = UpdateHistory.record(device, :failed, timestamp: recent)

      device = reload(device)

      assert device.consecutive_failed_updates == 1
      assert DateTime.diff(device.first_update_failure_at, recent, :second) == 0
    end

    test "is kept whether or not the history row can be written", %{device: device} do
      # The counter is PostgreSQL and the history is analytics — a deployment
      # with no ClickHouse still has to be able to answer "how many in a row".
      analytics_enabled = Application.get_env(:nerves_hub, :analytics_enabled)
      Application.put_env(:nerves_hub, :analytics_enabled, false)
      on_exit(fn -> Application.put_env(:nerves_hub, :analytics_enabled, analytics_enabled) end)

      :ok = UpdateHistory.record(device, :failed)

      assert reload(device).consecutive_failed_updates == 1
    end
  end

  describe "update_outcomes_by_date/5" do
    test "buckets successes and failures per day, zero filling the rest", %{
      device: device,
      org: org,
      product: product
    } do
      today = Date.utc_today()
      yesterday = Date.add(today, -1)

      record_at(device, :succeeded, yesterday)
      record_at(device, :failed, yesterday)
      record_at(device, :expired, yesterday)
      record_at(device, :succeeded, today)

      # A reschedule is a deferral, so it is stored but never plotted.
      record_at(device, :rescheduled, today)

      from = Date.add(today, -14)
      buckets = fn -> UpdateHistory.update_outcomes_by_date(org.id, product.id, from, today, "Etc/UTC") end

      :ok = Buffer.flush(DeviceUpdateHistory)
      assert_eventually(Enum.sum_by(buckets.(), &(&1.succeeded + &1.failed)) == 4)

      by_day = Map.new(buckets.(), &{&1.day, &1})

      # a bucket per day, inclusive of both ends
      assert map_size(by_day) == 15

      assert by_day[yesterday].succeeded == 1
      assert by_day[yesterday].failed == 2

      assert by_day[today].succeeded == 1
      assert by_day[today].failed == 0

      assert by_day[Date.add(today, -5)].succeeded == 0
      assert by_day[Date.add(today, -5)].failed == 0
    end

    test "only counts the product it was asked about", %{
      device: device,
      org: org,
      user: user,
      product: product
    } do
      other_product = Fixtures.product_fixture(user, org, %{name: "Somewhere Else"})

      today = Date.utc_today()
      from = Date.add(today, -1)

      record_at(device, :failed, today)

      failures = fn product_id ->
        org.id
        |> UpdateHistory.update_outcomes_by_date(product_id, from, today, "Etc/UTC")
        |> Enum.sum_by(& &1.failed)
      end

      :ok = Buffer.flush(DeviceUpdateHistory)
      assert_eventually(failures.(product.id) == 1)

      assert failures.(other_product.id) == 0
    end
  end

  describe "update_outcomes_by_hour/5" do
    test "buckets successes and failures per hour, zero filling the rest", %{
      device: device,
      org: org,
      product: product
    } do
      to = %{DateTime.utc_now() | minute: 0, second: 0, microsecond: {0, 0}}
      from = DateTime.add(to, -24, :hour)
      two_hours_ago = DateTime.add(to, -2, :hour)

      :ok = UpdateHistory.record(device, :failed, timestamp: two_hours_ago)
      :ok = UpdateHistory.record(device, :succeeded, timestamp: two_hours_ago)

      buckets = fn -> UpdateHistory.update_outcomes_by_hour(org.id, product.id, from, to, "Etc/UTC") end

      :ok = Buffer.flush(DeviceUpdateHistory)
      assert_eventually(Enum.sum_by(buckets.(), &(&1.succeeded + &1.failed)) == 2)

      # an hour bucket per hour in the window, inclusive of both ends
      assert length(buckets.()) == 25
      assert Enum.sum_by(buckets.(), & &1.failed) == 1
      assert Enum.sum_by(buckets.(), & &1.succeeded) == 1
    end
  end

  # Midday keeps the row on the day intended whichever timezone the query
  # buckets in, rather than landing it on a neighbour by a couple of hours.
  defp record_at(device, status, %Date{} = date) do
    timestamp = DateTime.new!(date, ~T[12:00:00], "Etc/UTC")

    :ok = UpdateHistory.record(device, status, timestamp: timestamp)
  end
end
