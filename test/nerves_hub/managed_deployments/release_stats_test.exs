defmodule NervesHub.ManagedDeployments.ReleaseStatsTest do
  # Not async: these tests read and write the AnalyticsRepo (ClickHouse), which
  # does not support concurrent writes.
  use NervesHub.DataCase, async: false
  use AssertEventually, timeout: 2000, interval: 50

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices.DeviceUpdateHistory
  alias NervesHub.Devices.UpdateHistory
  alias NervesHub.Devices.UpdateStat
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHub.ManagedDeployments.ReleaseStats

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    old = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})
    new = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(old, %{user: user})

    {:ok, _} = ManagedDeployments.create_deployment_release(deployment_group, new, nil, user, %{}, broadcast: false)

    now = DateTime.utc_now()
    first_from = DateTime.add(now, -3, :day)
    second_from = DateTime.add(now, -1, :day)

    [first, second] =
      for {number, at} <- [{1, first_from}, {2, second_from}] do
        {1, [release]} =
          DeploymentRelease
          |> where(deployment_group_id: ^deployment_group.id, number: ^number)
          |> select([r], r)
          |> Repo.update_all(set: [inserted_at: DateTime.to_naive(DateTime.truncate(at, :second))])

        Repo.preload(release, :firmware)
      end

    devices = for _ <- 1..3, do: Fixtures.device_fixture(org, product, old)

    AnalyticsRepo.query!("TRUNCATE TABLE device_update_history")
    on_exit(fn -> AnalyticsRepo.query!("TRUNCATE TABLE device_update_history") end)

    %{
      deployment_group: deployment_group,
      product: product,
      old: old,
      new: new,
      first: first,
      second: second,
      devices: devices,
      now: now
    }
  end

  defp stat!(device, deployment_group, attrs) do
    {at, attrs} = Map.pop!(attrs, :at)

    %UpdateStat{}
    |> Ecto.Changeset.change(
      Map.merge(
        %{
          device_id: device.id,
          product_id: device.product_id,
          deployment_id: deployment_group.id,
          type: "fwup_full",
          update_bytes: 0,
          saved_bytes: 0,
          inserted_at: DateTime.to_naive(DateTime.truncate(at, :second)),
          updated_at: DateTime.to_naive(DateTime.truncate(at, :second))
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  describe "windows/1" do
    test "runs each release until the next one, newest first", %{first: first, second: second} do
      assert [newest, oldest] = ReleaseStats.windows([first, second])

      assert newest.release.id == second.id
      assert newest.to == nil
      assert oldest.release.id == first.id
      assert oldest.to == newest.from
    end
  end

  describe "downloads_by_release/1 and downloads_by_source/2" do
    test "count each release's updates inside its window", context do
      %{deployment_group: deployment_group, devices: [a, b, c], old: old, new: new, now: now} = context

      stat!(a, deployment_group, %{target_firmware_uuid: old.uuid, update_bytes: 100, at: DateTime.add(now, -2, :day)})

      stat!(b, deployment_group, %{
        target_firmware_uuid: new.uuid,
        source_firmware_uuid: old.uuid,
        type: "fwup_delta",
        update_bytes: 10,
        saved_bytes: 90,
        at: now
      })

      stat!(c, deployment_group, %{target_firmware_uuid: new.uuid, update_bytes: 100, at: now})

      # the old firmware again, but after the first release was replaced
      stat!(c, deployment_group, %{target_firmware_uuid: old.uuid, update_bytes: 100, at: now})

      downloads = ReleaseStats.downloads_by_release(deployment_group)

      assert %{updated: 1, downloaded: 100, saved: 0} = downloads[context.first.id]
      assert %{updated: 2, downloaded: 110, saved: 90} = downloads[context.second.id]

      [_, newest] = ReleaseStats.windows([context.first, context.second]) |> Enum.reverse()

      assert newest |> then(&ReleaseStats.downloads_by_source(deployment_group, &1)) |> Enum.sort_by(& &1.delta?) == [
               %{source_uuid: nil, delta?: false, updated: 1, downloaded: 100, saved: 0},
               %{source_uuid: old.uuid, delta?: true, updated: 1, downloaded: 10, saved: 90}
             ]
    end
  end

  describe "kept?/2" do
    test "says whether a release's first update ended after the history began", %{now: now} do
      began = now

      assert ReleaseStats.kept?(began, nil)
      assert ReleaseStats.kept?(nil, %{first_at: nil})
      refute ReleaseStats.kept?(nil, %{first_at: now})
      assert ReleaseStats.kept?(began, %{first_at: DateTime.add(now, 1, :day)})
      # written a moment apart in the same transaction
      assert ReleaseStats.kept?(began, %{first_at: DateTime.add(now, -1)})
      refute ReleaseStats.kept?(began, %{first_at: DateTime.add(now, -1, :day)})
    end
  end

  describe "from the update history" do
    setup context do
      %{deployment_group: deployment_group, devices: [a, b, c], old: old, new: new, now: now} = context
      group = deployment_group.id

      record = fn device, status, opts ->
        :ok = UpdateHistory.record(device, status, Keyword.put(opts, :deployment_id, group))
      end

      # The first release: one success.
      record.(a, :succeeded,
        target_firmware_uuid: old.uuid,
        timestamp: DateTime.add(now, -2, :day),
        started_at: DateTime.add(now, -2, :day) |> DateTime.add(-100)
      )

      # The second: a delta that took 3 minutes, a full update that took 11, a
      # device that failed then took it, and a reschedule.
      record.(a, :succeeded,
        source_firmware_uuid: old.uuid,
        target_firmware_uuid: new.uuid,
        timestamp: DateTime.add(now, -60),
        started_at: DateTime.add(now, -240)
      )

      record.(b, :failed,
        target_firmware_uuid: new.uuid,
        reason: "fwup error",
        timestamp: DateTime.add(now, -20, :hour)
      )

      record.(b, :succeeded,
        target_firmware_uuid: new.uuid,
        timestamp: DateTime.add(now, -30),
        started_at: DateTime.add(now, -690)
      )

      record.(c, :abandoned, target_firmware_uuid: new.uuid, timestamp: DateTime.add(now, -10, :hour))
      record.(c, :rescheduled, target_firmware_uuid: new.uuid, timestamp: DateTime.add(now, -9, :hour))

      # Another group's, which isn't counted.
      :ok = UpdateHistory.record(c, :failed, deployment_id: group + 1, target_firmware_uuid: new.uuid)

      :ok = Buffer.flush(DeviceUpdateHistory)

      assert_eventually(AnalyticsRepo.aggregate(DeviceUpdateHistory, :count) == 7)

      :ok
    end

    test "history_began/1 finds the first outcome and the first duration", %{
      deployment_group: deployment_group,
      now: now
    } do
      assert %{outcomes: outcomes, durations: durations} = ReleaseStats.history_began(deployment_group)

      assert DateTime.diff(outcomes, DateTime.add(now, -2, :day)) == 0
      assert DateTime.diff(durations, DateTime.add(now, -2, :day)) == 0
    end

    test "outcomes_by_release/2 counts each release's attempts inside its window", context do
      windows = ReleaseStats.windows([context.first, context.second])

      assert %{releases: releases, median: median} = ReleaseStats.outcomes_by_release(context.deployment_group, windows)

      assert releases[context.first.id] == %{succeeded: 1, failed: 0, rescheduled: 0, median: 100}
      assert releases[context.second.id] == %{succeeded: 2, failed: 2, rescheduled: 1, median: 180}
      assert median == 180
    end

    test "release_detail/4 explains one release", context do
      %{deployment_group: deployment_group, old: old, now: now} = context
      [newest, _] = ReleaseStats.windows([context.first, context.second])

      detail = ReleaseStats.release_detail(deployment_group, newest, [old.uuid], now)

      assert detail.attempts == %{succeeded: 2, failed: 2, rescheduled: 1}
      assert detail.failed_devices == 2
      assert detail.recovered_devices == 1

      assert detail.timeline.bucket_seconds == 3600
      assert Enum.sum(for {_bucket, ok, _failed} <- detail.timeline.buckets, do: ok) == 2
      assert Enum.sum(for {_bucket, _ok, failed} <- detail.timeline.buckets, do: failed) == 2

      assert detail.durations.buckets == %{1 => %{delta: 1, full: 0}, 5 => %{delta: 0, full: 1}}
      assert detail.durations.delta_median == 180
      assert detail.durations.full_median == 660

      assert [
               %{status: :abandoned, reason: nil, count: 1},
               %{status: :failed, reason: "fwup error", count: 1}
             ] = Enum.sort_by(detail.reasons, & &1.status)

      assert %{succeeded: 1, failed: 0, median: 180} = Enum.find(detail.sources, &(&1.uuid == old.uuid))
      assert %{succeeded: 1, failed: 2, median: 660} = Enum.find(detail.sources, &(&1.uuid == ""))
    end
  end
end
