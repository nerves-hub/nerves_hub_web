defmodule NervesHub.Devices.UpdateHistoryTest do
  # Not async: these tests read and write the AnalyticsRepo (ClickHouse), which
  # does not support concurrent writes.
  use NervesHub.DataCase, async: false
  use AssertEventually, timeout: 2000, interval: 50

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices
  alias NervesHub.Devices.DeviceUpdateHistory
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Devices.UpdateHistory
  alias NervesHub.Firmwares
  alias NervesHub.FirmwareUpdates
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

  describe "device_attempts/3" do
    test "pages a device's attempts newest first, naming the firmware and deployment group", %{
      device: device,
      firmware: firmware,
      org: org,
      product: product,
      user: user
    } do
      deployment_group = Fixtures.deployment_group_fixture(firmware, %{name: "beta", user: user})
      now = DateTime.utc_now()

      :ok =
        UpdateHistory.record(device, :failed,
          deployment_id: deployment_group.id,
          target_firmware_uuid: firmware.uuid,
          reason: "fwup error",
          timestamp: DateTime.add(now, -60)
        )

      :ok = UpdateHistory.record(device, :succeeded, target_firmware_uuid: firmware.uuid, timestamp: now)

      other = Fixtures.device_fixture(org, product, firmware)
      :ok = UpdateHistory.record(other, :failed)
      :ok = Buffer.flush(DeviceUpdateHistory)

      assert_eventually(
        {[latest, earlier], %{total_count: 2, total_pages: 1}} = UpdateHistory.device_attempts(device, 1, 25)
      )

      assert latest.status == :succeeded
      assert latest.target == %{uuid: firmware.uuid, version: firmware.version, available?: true}
      assert latest.deployment_group == nil

      assert earlier.status == :failed
      assert earlier.reason == "fwup error"
      assert earlier.deployment_group == %{id: deployment_group.id, name: "beta"}

      assert {[^earlier], %{current_page: 2}} = UpdateHistory.device_attempts(device, 2, 1)
    end

    test "clamps a page and page size taken from the URL", %{device: device, firmware: firmware} do
      :ok = UpdateHistory.record(device, :succeeded, target_firmware_uuid: firmware.uuid)
      :ok = Buffer.flush(DeviceUpdateHistory)

      assert_eventually({[_attempt], %{current_page: 1, page_size: 1}} = UpdateHistory.device_attempts(device, 0, 0))
      assert {[_attempt], %{current_page: 1, page_size: 100}} = UpdateHistory.device_attempts(device, -3, 1_000_000)
    end

    test "is empty without querying ClickHouse where analytics is off", %{device: device} do
      original = Application.get_env(:nerves_hub, :analytics_enabled)
      Application.put_env(:nerves_hub, :analytics_enabled, false)
      on_exit(fn -> Application.put_env(:nerves_hub, :analytics_enabled, original) end)

      assert {[], %{current_page: 1, page_size: 25, total_count: 0, total_pages: 0}} =
               UpdateHistory.device_attempts(device, 2, 25)
    end
  end

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
      # Yesterday rather than a fixed date, which the table's TTL would expire.
      at = DateTime.new!(Date.add(Date.utc_today(), -1), ~T[04:05:06], "Etc/UTC")

      :ok = UpdateHistory.record(device, :expired, timestamp: at)

      assert_eventually([row] = history_for(device))

      assert DateTime.compare(row.timestamp, at) == :eq
    end

    test "records how long the attempt took from when the update was sent", %{device: device} do
      ended_at = DateTime.utc_now()

      :ok = UpdateHistory.record(device, :succeeded, timestamp: ended_at, started_at: DateTime.add(ended_at, -330))

      # inflight rows carry naive timestamps
      sent_naive = ended_at |> DateTime.add(-90) |> DateTime.to_naive()
      :ok = UpdateHistory.record(device, :succeeded, timestamp: ended_at, started_at: sent_naive)

      # a clock that moved backwards is not a negative duration
      :ok = UpdateHistory.record(device, :succeeded, timestamp: ended_at, started_at: DateTime.add(ended_at, 60))

      :ok = UpdateHistory.record(device, :succeeded, timestamp: ended_at)

      assert_eventually(length(history_for(device)) == 4)

      assert device |> history_for() |> Enum.map(& &1.duration_seconds) |> Enum.sort() == [0, 0, 90, 330]
    end

    test "every status is recordable", %{device: device} do
      for status <- UpdateHistory.statuses() do
        :ok = UpdateHistory.record(device, status)
      end

      expected = Enum.map(UpdateHistory.statuses(), &Atom.to_string/1)

      assert_eventually(Enum.sort(Enum.map(history_for(device), & &1.status)) == Enum.sort(expected))
    end
  end

  describe "a device rejoining on the firmware it was sent" do
    test "records how long the update took", %{
      device: device,
      firmware: firmware,
      org: org,
      product: product,
      user: user,
      tmp_dir: tmp_dir
    } do
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      target = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})
      deployment_group = Fixtures.deployment_group_fixture(target, %{user: user})

      sent_at =
        DateTime.utc_now() |> DateTime.add(-4, :minute) |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)

      {:ok, _} =
        deployment_group
        |> InflightUpdate.deployment_requested_changeset(device.id, false)
        |> Ecto.Changeset.put_change(:inserted_at, sent_at)
        |> Repo.insert()

      {:ok, source_metadata} = Firmwares.metadata_from_firmware(firmware)
      {:ok, target_metadata} = Firmwares.metadata_from_firmware(target)
      {:ok, device} = Devices.update_firmware_metadata(device, target_metadata, :unknown, false)

      assert {:ok, _device} = FirmwareUpdates.firmware_update_successful(device, source_metadata)

      assert_eventually([row] = history_for(device))

      assert row.status == "succeeded"
      assert row.deployment_id == deployment_group.id
      assert row.duration_seconds in 240..250
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

  describe "failed_attempts_count/4" do
    test "counts failed attempts to move the product's devices to one firmware since a time", %{
      device: device,
      firmware: firmware,
      org: org,
      product: product
    } do
      now = DateTime.utc_now()
      record = fn status, opts -> :ok = UpdateHistory.record(device, status, opts) end

      record.(:failed, target_firmware_uuid: firmware.uuid, timestamp: DateTime.add(now, -1, :day))
      record.(:expired, target_firmware_uuid: firmware.uuid, timestamp: DateTime.add(now, -2, :day))

      # Not failures, too old, or another firmware.
      record.(:succeeded, target_firmware_uuid: firmware.uuid, timestamp: now)
      record.(:rescheduled, target_firmware_uuid: firmware.uuid, timestamp: now)
      record.(:failed, target_firmware_uuid: firmware.uuid, timestamp: DateTime.add(now, -8, :day))
      record.(:failed, target_firmware_uuid: Ecto.UUID.generate(), timestamp: now)

      since = DateTime.add(now, -7, :day)
      :ok = Buffer.flush(DeviceUpdateHistory)

      assert_eventually(UpdateHistory.failed_attempts_count(org.id, product.id, firmware.uuid, since) == 2)
      assert UpdateHistory.failed_attempts_count(org.id, product.id + 1, firmware.uuid, since) == 0
    end
  end
end
