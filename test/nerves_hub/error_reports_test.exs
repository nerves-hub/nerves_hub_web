defmodule NervesHub.ErrorReportsTest do
  # Not async: these touch the AnalyticsRepo, which is a ClickHouse database
  # that does not support concurrent writes.
  use NervesHub.DataCase, async: false

  import Ecto.Query

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.ErrorReports
  alias NervesHub.ErrorReports.ErrorGroup
  alias NervesHub.ErrorReports.ErrorReport
  alias NervesHub.ErrorReports.GroupBuffer
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware, %{status: :provisioned})
    other_device = Fixtures.device_fixture(org, product, firmware)

    :ok = Buffer.flush(ErrorReport)
    :ok = GroupBuffer.flush()
    AnalyticsRepo.query("TRUNCATE TABLE device_error_reports", [])

    %{
      user: user,
      org: org,
      product: product,
      device: device,
      other_device: other_device,
      device_info: device_info(device)
    }
  end

  defp device_info(device, firmware_uuid \\ "fw-connection") do
    %DeviceInfo{
      org_id: device.org_id,
      product_id: device.product_id,
      device_id: device.id,
      device_identifier: device.identifier,
      firmware_metadata: %{uuid: firmware_uuid}
    }
  end

  defp report(overrides \\ %{}) do
    Map.merge(
      %{
        "timestamp" => "2026-08-31T10:00:00.000000Z",
        "kind" => "error",
        "reason" => "** (RuntimeError) boom",
        "frames" => [%{"module" => "MyApp.Worker", "function" => "run/0", "file" => "w.ex", "line" => 3}]
      },
      overrides
    )
  end

  defp settle() do
    :ok = Buffer.flush(ErrorReport)
    :ok = GroupBuffer.flush()
  end

  defp groups(product) do
    Repo.all(from(g in ErrorGroup, where: g.product_id == ^product.id, order_by: g.id))
  end

  describe "record_batch/2" do
    test "writes an occurrence and a group", %{device_info: info, product: product, device: device} do
      assert {:ok, 1} = ErrorReports.record_batch(info, [report()])
      settle()

      assert [group] = groups(product)
      assert group.occurrence_count == 1
      assert group.reason == "** (RuntimeError) boom"
      assert group.top_frame_module == "MyApp.Worker"
      assert group.status == :unresolved

      assert [occurrence] = AnalyticsRepo.all(ErrorReport)
      assert occurrence.device_id == device.id
      assert occurrence.product_id == product.id
      assert occurrence.org_id == device.org_id
      assert occurrence.fingerprint == group.fingerprint
    end

    test "two occurrences of one bug make one group", %{device_info: info, product: product} do
      {:ok, 2} =
        ErrorReports.record_batch(info, [
          report(%{"reason" => "boom in #PID<0.1.0>"}),
          report(%{"reason" => "boom in #PID<0.2.0>", "timestamp" => "2026-08-31T10:00:01.000000Z"})
        ])

      settle()

      assert [%ErrorGroup{occurrence_count: 2}] = groups(product)
      assert AnalyticsRepo.aggregate(ErrorReport, :count) == 2
    end

    test "an unreadable report is skipped and its neighbours are kept", %{
      device_info: info,
      product: product
    } do
      assert {:ok, 2} =
               ErrorReports.record_batch(info, [
                 report(),
                 Map.delete(report(), "timestamp"),
                 report(%{"reason" => "a different bug"})
               ])

      settle()

      assert length(groups(product)) == 2
      assert AnalyticsRepo.aggregate(ErrorReport, :count) == 2
    end

    test "an empty batch does nothing", %{device_info: info, product: product} do
      assert {:ok, 0} = ErrorReports.record_batch(info, [])
      settle()

      assert groups(product) == []
    end

    test "frames are stored as JSON and read back", %{device_info: info} do
      {:ok, 1} = ErrorReports.record_batch(info, [report()])
      settle()

      assert [occurrence] = AnalyticsRepo.all(ErrorReport)

      assert ErrorReport.frames(occurrence) == [
               %{"module" => "MyApp.Worker", "function" => "run/0", "file" => "w.ex", "line" => 3}
             ]
    end

    test "credential-shaped context is redacted before storage", %{device_info: info} do
      {:ok, 1} = ErrorReports.record_batch(info, [report(%{"context" => %{"token" => "sekrit"}})])
      settle()

      assert [%ErrorReport{context: %{"token" => "[redacted]"}}] = AnalyticsRepo.all(ErrorReport)
    end
  end

  describe "firmware attribution" do
    test "the device's own firmware_uuid wins", %{device_info: info} do
      {:ok, 1} = ErrorReports.record_batch(info, [report(%{"firmware_uuid" => "fw-reported"})])
      settle()

      assert [%ErrorReport{firmware_uuid: "fw-reported"}] = AnalyticsRepo.all(ErrorReport)
    end

    test "the connection's metadata is the fallback", %{device_info: info} do
      {:ok, 1} = ErrorReports.record_batch(info, [report()])
      settle()

      assert [%ErrorReport{firmware_uuid: "fw-connection"}] = AnalyticsRepo.all(ErrorReport)
    end
  end

  describe "device-supplied fingerprints" do
    test "group two unrelated errors together", %{device_info: info, product: product} do
      {:ok, 2} =
        ErrorReports.record_batch(info, [
          report(%{"reason" => "gateway timed out", "fingerprint" => "payments"}),
          report(%{"reason" => "gateway refused", "fingerprint" => "payments"})
        ])

      settle()

      assert [%ErrorGroup{occurrence_count: 2}] = groups(product)
    end
  end

  describe "groups_for_product/2" do
    setup %{device_info: info} do
      {:ok, 3} =
        ErrorReports.record_batch(info, [
          report(%{"reason" => "alpha failure", "timestamp" => "2026-08-29T10:00:00.000000Z"}),
          report(%{"reason" => "beta failure", "timestamp" => "2026-08-30T10:00:00.000000Z"}),
          report(%{"reason" => "gamma failure", "timestamp" => "2026-08-31T10:00:00.000000Z"})
        ])

      settle()
      :ok
    end

    test "returns groups newest-seen first by default", %{product: product} do
      {groups, meta} = ErrorReports.groups_for_product(product)

      assert meta.total_count == 3
      assert Enum.map(groups, & &1.reason) == ["gamma failure", "beta failure", "alpha failure"]
    end

    test "filters by status", %{product: product, user: user} do
      [first | _rest] = groups(product)
      {:ok, _resolved} = ErrorReports.resolve(first, user)

      {unresolved, _meta} = ErrorReports.groups_for_product(product, status: :unresolved)
      {resolved, _meta} = ErrorReports.groups_for_product(product, status: :resolved)

      assert length(unresolved) == 2
      assert length(resolved) == 1
    end

    test "searches the reason, case-insensitively", %{product: product} do
      {groups, _meta} = ErrorReports.groups_for_product(product, search: "BETA")

      assert Enum.map(groups, & &1.reason) == ["beta failure"]
    end

    # `%` is an `ilike` wildcard; a reason containing one should still be findable.
    test "takes the search text literally", %{device_info: info, product: product} do
      {:ok, 1} = ErrorReports.record_batch(info, [report(%{"reason" => "disk at 100% capacity"})])
      settle()

      {matched, _meta} = ErrorReports.groups_for_product(product, search: "100%")
      assert Enum.map(matched, & &1.reason) == ["disk at 100% capacity"]

      {none, _meta} = ErrorReports.groups_for_product(product, search: "%zzz%")
      assert none == []
    end

    test "sorts by occurrence count", %{device_info: info, product: product} do
      {:ok, 2} =
        ErrorReports.record_batch(info, [
          report(%{"reason" => "alpha failure", "timestamp" => "2026-08-29T11:00:00.000000Z"}),
          report(%{"reason" => "alpha failure", "timestamp" => "2026-08-29T12:00:00.000000Z"})
        ])

      settle()

      {groups, _meta} = ErrorReports.groups_for_product(product, sort: :count)
      assert hd(groups).reason == "alpha failure"
    end

    test "paginates", %{product: product} do
      {groups, meta} = ErrorReports.groups_for_product(product, page: 2, page_size: 2)

      assert length(groups) == 1
      assert meta.total_count == 3
    end
  end

  describe "status_counts/1" do
    test "counts every status, including the empty ones", %{
      device_info: info,
      product: product,
      user: user
    } do
      {:ok, 2} =
        ErrorReports.record_batch(info, [
          report(%{"reason" => "one"}),
          report(%{"reason" => "two"})
        ])

      settle()

      [first | _rest] = groups(product)
      {:ok, _muted} = ErrorReports.mute(first, user)

      assert ErrorReports.status_counts(product) == %{unresolved: 1, resolved: 0, muted: 1}
    end
  end

  describe "get_group!/2" do
    test "is scoped to the product", %{device_info: info, product: product, user: user, org: org} do
      {:ok, 1} = ErrorReports.record_batch(info, [report()])
      settle()

      [group] = groups(product)
      other_product = Fixtures.product_fixture(user, org, %{name: "Another"})

      assert ErrorReports.get_group!(product, group.id).id == group.id

      assert_raise Ecto.NoResultsError, fn ->
        ErrorReports.get_group!(other_product, group.id)
      end
    end
  end

  describe "groups_for_device/2" do
    test "counts only this device's occurrences", %{
      device: device,
      other_device: other_device,
      device_info: info
    } do
      {:ok, 2} =
        ErrorReports.record_batch(info, [
          report(),
          report(%{"timestamp" => "2026-08-31T10:00:01.000000Z"})
        ])

      {:ok, 1} = ErrorReports.record_batch(device_info(other_device), [report()])
      settle()

      assert [entry] = ErrorReports.groups_for_device(device)
      assert entry.device_occurrence_count == 2
      assert entry.group.occurrence_count == 3

      assert [other] = ErrorReports.groups_for_device(other_device)
      assert other.device_occurrence_count == 1
    end

    test "a device with nothing reported has no rows", %{other_device: other_device} do
      assert ErrorReports.groups_for_device(other_device) == []
    end

    # ClickHouse keeps the fingerprint; PostgreSQL is where it means something.
    test "drops occurrences whose group row is gone", %{device: device, device_info: info} do
      {:ok, 1} = ErrorReports.record_batch(info, [report()])
      settle()

      Repo.delete_all(ErrorGroup)

      assert ErrorReports.groups_for_device(device) == []
    end

    test "ignores occurrences outside the window", %{device: device, device_info: info} do
      {:ok, 1} = ErrorReports.record_batch(info, [report()])
      settle()

      future = DateTime.add(DateTime.utc_now(), 1, :day)
      assert ErrorReports.groups_for_device(device, since: future) == []
    end
  end

  describe "drill-downs" do
    setup %{device_info: info, device: device, other_device: other_device, product: product} do
      {:ok, 2} =
        ErrorReports.record_batch(info, [
          report(%{"timestamp" => "2026-08-30T10:00:00.000000Z"}),
          report(%{"timestamp" => "2026-08-31T10:00:00.000000Z", "message" => "the newest one"})
        ])

      # Deliberately not sharing a timestamp with either of the above: "the
      # newest occurrence" has no single answer when two of them tie.
      {:ok, 1} =
        ErrorReports.record_batch(device_info(other_device), [
          report(%{"timestamp" => "2026-08-29T10:00:00.000000Z"})
        ])

      settle()

      [group] = groups(product)
      %{group: group, device: device}
    end

    test "occurrences come back newest first", %{group: group} do
      assert [newest, older, _third] = ErrorReports.occurrences(group)
      assert DateTime.after?(newest.timestamp, older.timestamp)
    end

    test "occurrences can be narrowed to one device", %{group: group, device: device} do
      occurrences = ErrorReports.occurrences(group, device_id: device.id)

      assert length(occurrences) == 2
      assert Enum.all?(occurrences, &(&1.device_id == device.id))
    end

    test "the :before cursor excludes the row it names", %{group: group} do
      [newest | _rest] = ErrorReports.occurrences(group)
      next_page = ErrorReports.occurrences(group, before: newest.timestamp)

      refute Enum.any?(next_page, &(&1.timestamp == newest.timestamp))
    end

    test "latest_occurrence/2 is the newest", %{group: group} do
      assert ErrorReports.latest_occurrence(group).message == "the newest one"
    end

    test "latest_occurrence/2 can be scoped to a device", %{group: group, device: device} do
      assert ErrorReports.latest_occurrence(group, device_id: device.id).message == "the newest one"
    end

    test "affected_device_count/1 counts distinct devices", %{group: group} do
      assert ErrorReports.affected_device_count(group) == 2
    end

    test "affected_devices/2 returns devices with their counts", %{group: group, device: device} do
      entries = ErrorReports.affected_devices(group)

      assert length(entries) == 2
      assert Enum.find(entries, &(&1.device.id == device.id)).occurrence_count == 2
    end

    test "affected_devices/2 drops devices that no longer exist", %{group: group, device: device} do
      Repo.delete!(device)

      entries = ErrorReports.affected_devices(group)

      assert length(entries) == 1
      refute Enum.any?(entries, &(&1.device.id == device.id))
    end

    test "occurrences_by_date/4 fills the quiet days", %{group: group} do
      buckets = ErrorReports.occurrences_by_date(group, ~D[2026-08-28], ~D[2026-09-01], "Etc/UTC")

      assert length(buckets) == 5
      assert Enum.map(buckets, & &1.date) |> List.first() == ~D[2026-08-28]
      assert Enum.find(buckets, &(&1.date == ~D[2026-08-28])).count == 0
      assert Enum.find(buckets, &(&1.date == ~D[2026-08-29])).count == 1
      assert Enum.find(buckets, &(&1.date == ~D[2026-08-30])).count == 1
      assert Enum.find(buckets, &(&1.date == ~D[2026-08-31])).count == 1
      assert Enum.find(buckets, &(&1.date == ~D[2026-08-29])).device_count == 1
    end
  end

  describe "lifecycle" do
    setup %{device_info: info, product: product} do
      {:ok, 1} = ErrorReports.record_batch(info, [report()])
      settle()

      [group] = groups(product)
      %{group: group}
    end

    test "resolve/3 records who and when", %{group: group, user: user} do
      assert {:ok, resolved} = ErrorReports.resolve(group, user, "fw-with-fix")

      assert resolved.status == :resolved
      assert resolved.resolved_by_id == user.id
      assert resolved.resolved_in_firmware_uuid == "fw-with-fix"
      assert resolved.resolved_at
    end

    test "mute/2 records who and when", %{group: group, user: user} do
      assert {:ok, muted} = ErrorReports.mute(group, user)

      assert muted.status == :muted
      assert muted.muted_by_id == user.id
      assert muted.muted_at
    end

    test "reopen/1 clears both", %{group: group, user: user} do
      {:ok, muted} = ErrorReports.mute(group, user)

      assert {:ok, reopened} = ErrorReports.reopen(muted)
      assert reopened.status == :unresolved
      assert reopened.muted_at == nil
      assert reopened.muted_by_id == nil
    end

    test "resolving after a regression clears the regressed marker", %{group: group, user: user} do
      {:ok, _resolved} = ErrorReports.resolve(group, user)
      {:ok, regressed} = group |> Ecto.Changeset.change(%{regressed_at: DateTime.utc_now()}) |> Repo.update()

      assert {:ok, again} = ErrorReports.resolve(regressed, user)
      assert again.regressed_at == nil
    end
  end
end
