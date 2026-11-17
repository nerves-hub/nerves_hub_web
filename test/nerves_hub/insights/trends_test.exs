defmodule NervesHub.Insights.TrendsTest do
  # Not async: the trends read the AnalyticsRepo (ClickHouse).
  use NervesHub.DataCase, async: false
  use AssertEventually, timeout: 2000, interval: 50

  import Ecto.Query

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.DeviceConnectionHistory
  alias NervesHub.Devices.DeviceHealthHistory
  alias NervesHub.Devices.DeviceUpdateHistory
  alias NervesHub.Devices.Health
  alias NervesHub.Devices.UpdateHistory
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Fixtures
  alias NervesHub.Insights
  alias NervesHub.Insights.Trends
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHub.Repo

  @moduletag :tmp_dir

  # Midday, so a day's bucket boundaries are well clear of the rows below.
  @now ~U[2026-11-17 12:00:00.000000Z]

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    uploaded(firmware, ago(11 * 24))

    %{user: user, org: org, org_key: org_key, product: product, firmware: firmware, device: device}
  end

  defp ago(hours), do: DateTime.add(@now, -hours * 3600, :second)

  defp uploaded(firmware, at) do
    Repo.update_all(from(f in Firmware, where: f.id == ^firmware.id), set: [inserted_at: naive(at)])
  end

  defp released(firmware, user, at) do
    group = Fixtures.deployment_group_fixture(firmware, %{user: user})

    Repo.update_all(from(r in DeploymentRelease, where: r.deployment_group_id == ^group.id),
      set: [inserted_at: naive(at)]
    )
  end

  defp naive(at), do: at |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)

  defp trends(product, period \\ "14d", time_zone \\ "Etc/UTC") do
    Trends.trends(product, Insights.composition(product, @now), period, time_zone, @now)
  end

  defp record_update(device, status, at, opts \\ []) do
    :ok = UpdateHistory.record(device, status, Keyword.put(opts, :timestamp, at))
  end

  defp recorded(schema, device, count) do
    :ok = Buffer.flush(schema)

    assert_eventually(length(Enum.filter(AnalyticsRepo.all(schema), &(&1.device_id == device.id))) == count)
  end

  # A connection from `established` that is still open when `disconnected` is
  # nil.
  defp connected(device, established, disconnected) do
    {:ok, _} =
      %DeviceConnection{
        id: Ecto.UUID.generate(version: 7),
        org_id: device.org_id,
        product_id: device.product_id,
        device_id: device.id,
        established_at: established,
        last_seen_at: disconnected || @now,
        disconnected_at: disconnected
      }
      |> DeviceConnectionHistory.from_device_connection_changeset()
      |> AnalyticsRepo.insert()
  end

  defp health(device, status, at) do
    Buffer.insert(
      DeviceHealthHistory,
      DeviceHealthHistory.changeset(%{
        timestamp: at,
        org_id: device.org_id,
        product_id: device.product_id,
        device_id: device.id,
        status: status,
        status_reasons: ""
      })
    )
  end

  defp zeroes(count, then), do: List.duplicate(0.0, count) ++ then

  describe "the buckets" do
    test "are hours over 24 hours and days over the longer periods, the last ending now", %{product: product} do
      for {period, count} <- [{"24h", 24}, {"14d", 14}, {"4w", 28}, {"90d", 90}] do
        trends = trends(product, period)

        assert length(trends.buckets) == count
        assert List.last(trends.buckets).until == @now
        assert trends.unit == if(period == "24h", do: :hour, else: :day)
      end
    end

    test "start at midnight in the viewer's time zone", %{product: product} do
      trends = trends(product, "14d", "Pacific/Auckland")

      assert trends.time_zone == "Pacific/Auckland"
      assert %DateTime{hour: 0, minute: 0, time_zone: "Pacific/Auckland"} = hd(trends.buckets).from
    end

    test "fall back to UTC for a time zone that doesn't exist", %{product: product} do
      trends = trends(product, "14d", "Mars/Olympus_Mons")

      assert trends.time_zone == "Etc/UTC"
      assert hd(trends.buckets).from == ~U[2026-11-04 00:00:00Z]
    end
  end

  describe "the updates" do
    test "count each bucket's successes and failures", %{product: product, device: device} do
      record_update(device, :succeeded, ago(24))
      record_update(device, :failed, ago(24))
      record_update(device, :abandoned, ago(24))
      record_update(device, :succeeded, ago(1))
      recorded(DeviceUpdateHistory, device, 4)

      updates = trends(product).updates

      assert length(updates) == 14
      assert Enum.at(updates, 12) == %{succeeded: 1, failed: 2}
      assert List.last(updates) == %{succeeded: 1, failed: 0}
      assert Enum.all?(Enum.take(updates, 12), &(&1 == %{succeeded: 0, failed: 0}))
    end

    test "leave a reschedule out of both, because deferring is not failing", %{product: product, device: device} do
      record_update(device, :rescheduled, ago(24))
      recorded(DeviceUpdateHistory, device, 1)

      assert Enum.all?(trends(product).updates, &(&1 == %{succeeded: 0, failed: 0}))
    end

    test "are zero for every bucket with no history", %{product: product} do
      assert trends(product).updates == List.duplicate(%{succeeded: 0, failed: 0}, 14)
    end
  end

  describe "the online share" do
    test "counts a device connected at the end of each bucket, and ends on the live figure", %{
      product: product,
      device: device
    } do
      # connected since the middle of the day before yesterday, and still
      # connected as far as the history knows; the live count says it isn't
      connected(device, ago(49), nil)

      assert trends(product).online == zeroes(11, [1.0, 1.0, 0.0])
    end

    test "leaves out a device that was away over a bucket's end", %{product: product, device: device} do
      # away over yesterday's end, back this morning
      connected(device, ago(49), ago(14))
      connected(device, ago(11), nil)

      assert trends(product).online == zeroes(11, [1.0, 0.0, 0.0])
    end
  end

  describe "the healthy share" do
    test "is walked back from the live count through the moves into healthy", %{product: product, device: device} do
      health(device, "unhealthy", ago(30 * 24))
      health(device, "healthy", ago(25))
      recorded(DeviceHealthHistory, device, 2)

      {:ok, _} =
        Health.save_device_health(%{
          "device_id" => device.id,
          "data" => %{},
          "status" => :healthy,
          "status_reasons" => %{}
        })

      assert trends(product).healthy == zeroes(12, [1.0, 1.0])
    end
  end

  describe "the adoption" do
    test "is walked back from the live versions through the updates that succeeded", ctx do
      newer = Fixtures.firmware_fixture(ctx.org_key, ctx.product, %{dir: ctx.tmp_dir, version: "2.0.0"})
      updated = Fixtures.device_fixture(ctx.org, ctx.product, newer)

      record_update(updated, :succeeded, ago(25),
        source_firmware_uuid: ctx.firmware.uuid,
        target_firmware_uuid: newer.uuid
      )

      recorded(DeviceUpdateHistory, updated, 1)

      adoption = trends(ctx.product).adoption
      version = ctx.firmware.version

      assert length(adoption) == 14
      assert List.last(adoption) == %{version => 1, "2.0.0" => 1}
      assert Enum.at(adoption, 12) == %{version => 1, "2.0.0" => 1}
      assert Enum.at(adoption, 11) == %{version => 2, "2.0.0" => 0}
      assert hd(adoption) == %{version => 2, "2.0.0" => 0}
    end
  end

  describe "the release" do
    test "is when a deployment group was first given the newest version", ctx do
      released(ctx.firmware, ctx.user, ago(9 * 24))
      released(ctx.firmware, ctx.user, ago(4 * 24))

      assert trends(ctx.product).release == %{
               version: ctx.firmware.version,
               at: DateTime.truncate(ago(9 * 24), :second)
             }
    end

    test "is the upload when no deployment group has had the newest version", ctx do
      assert trends(ctx.product).release == %{
               version: ctx.firmware.version,
               at: DateTime.truncate(ago(11 * 24), :second)
             }
    end

    test "is left out when it falls before the period", ctx do
      released(ctx.firmware, ctx.user, ago(9 * 24))

      assert trends(ctx.product, "24h").release == nil
      assert %{at: _} = trends(ctx.product, "14d").release
    end
  end
end
