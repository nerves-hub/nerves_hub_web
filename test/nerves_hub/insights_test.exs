defmodule NervesHub.InsightsTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Devices
  alias NervesHub.Devices.Health
  alias NervesHub.Firmwares
  alias NervesHub.Fixtures
  alias NervesHub.Insights
  alias NervesHub.Repo

  @moduletag :tmp_dir

  @now ~U[2026-11-17 12:00:00.000000Z]

  describe "composition/2" do
    setup %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      %{user: user, org: org, product: product, firmware: firmware}
    end

    test "is all zeroes for a product with no devices", %{product: product} do
      assert Insights.composition(product, @now) == %{
               total: 0,
               connection: %{online: 0, recent: 0, week: 0, stale: 0, never: 0},
               health: %{healthy: 0, warning: 0, unhealthy: 0, unknown: 0},
               active: 0,
               active_health: %{healthy: 0, warning: 0, unhealthy: 0, unknown: 0},
               versions: [],
               newest_version: nil
             }
    end

    test "groups devices by when they were last seen, as the devices list filters do", ctx do
      online = device(ctx, "1.0.0", status: :provisioned)
      Fixtures.device_connection_fixture(online, %{status: :connected, last_seen_at: @now})

      connecting = device(ctx, "1.0.0", status: :provisioned)
      Fixtures.device_connection_fixture(connecting, %{status: :connecting, last_seen_at: days_ago(30)})

      for {days, count} <- [{2, 2}, {10, 3}, {20, 4}], _ <- 1..count do
        seen = device(ctx, "1.0.0", status: :provisioned)
        Fixtures.device_connection_fixture(seen, %{status: :disconnected, last_seen_at: days_ago(days)})
      end

      # never connected
      device(ctx, "1.0.0", status: :registered)

      # provisioned, with no connection row: it last connected before
      # connection rows were kept, so long ago
      device(ctx, "1.0.0", status: :provisioned)

      composition = Insights.composition(ctx.product, @now)

      assert composition.total == 13
      assert composition.connection == %{online: 1, recent: 3, week: 3, stale: 5, never: 1}
    end

    test "counts in each connection group exactly the devices its filter lists", ctx do
      now = DateTime.utc_now()
      ago = &DateTime.add(now, -&1, :day)

      online = device(ctx, "1.0.0", status: :provisioned)
      Fixtures.device_connection_fixture(online, %{status: :connected, last_seen_at: now})

      connecting = device(ctx, "1.0.0", status: :provisioned)
      Fixtures.device_connection_fixture(connecting, %{status: :connecting, last_seen_at: ago.(30)})

      for days <- [2, 10, 20] do
        seen = device(ctx, "1.0.0", status: :provisioned)
        Fixtures.device_connection_fixture(seen, %{status: :disconnected, last_seen_at: ago.(days)})
      end

      device(ctx, "1.0.0", status: :registered)
      device(ctx, "1.0.0", status: :provisioned)

      counts = Insights.composition(ctx.product, now).connection

      for {group, filters} <- Insights.connection_filters() do
        opts = %{
          sort: {:asc, :identifier},
          filters: filters |> Map.new() |> Map.put(:display_deleted, "exclude"),
          pagination: %{page_size: 100}
        }

        {devices, _meta} = Devices.filter(ctx.product, ctx.user, opts)

        assert length(devices) == counts[group], "#{group}: #{inspect(filters)}"
      end

      opts = %{
        sort: {:asc, :identifier},
        filters: %{advanced_query: Insights.active_query(), display_deleted: "exclude"},
        pagination: %{page_size: 100}
      }

      {active, _meta} = Devices.filter(ctx.product, ctx.user, opts)

      assert length(active) == counts.online + counts.recent
    end

    test "counts a device that has never reported its health as unknown", ctx do
      for status <- [:healthy, :healthy, :warning, :unhealthy, :unknown] do
        ctx |> device("1.0.0") |> set_health(status)
      end

      device(ctx, "1.0.0")

      assert Insights.composition(ctx.product, @now).health == %{
               healthy: 2,
               warning: 1,
               unhealthy: 1,
               unknown: 2
             }
    end

    test "crosses health and connection with each firmware version", ctx do
      for _ <- 1..3, do: ctx |> device("2.0.0") |> set_health(:healthy)

      flaky = device(ctx, "1.0.0", status: :provisioned)
      set_health(flaky, :warning)
      Fixtures.device_connection_fixture(flaky, %{status: :connected, last_seen_at: @now})

      device(ctx, "1.0.0")
      device(ctx, nil)

      assert Insights.composition(ctx.product, @now).versions == [
               %{
                 version: "2.0.0",
                 count: 3,
                 health: %{healthy: 3, warning: 0, unhealthy: 0, unknown: 0},
                 offline: 3,
                 active: 0,
                 active_health: %{healthy: 0, warning: 0, unhealthy: 0, unknown: 0}
               },
               %{
                 version: "1.0.0",
                 count: 2,
                 health: %{healthy: 0, warning: 1, unhealthy: 0, unknown: 1},
                 offline: 1,
                 active: 1,
                 active_health: %{healthy: 0, warning: 1, unhealthy: 0, unknown: 0}
               },
               %{
                 version: nil,
                 count: 1,
                 health: %{healthy: 0, warning: 0, unhealthy: 0, unknown: 1},
                 offline: 1,
                 active: 0,
                 active_health: %{healthy: 0, warning: 0, unhealthy: 0, unknown: 0}
               }
             ]
    end

    test "counts as active only the devices online or seen in the last 7 days", ctx do
      online = device(ctx, "1.0.0", status: :provisioned)
      set_health(online, :unhealthy)
      Fixtures.device_connection_fixture(online, %{status: :connected, last_seen_at: @now})

      recent = device(ctx, "1.0.0", status: :provisioned)
      Fixtures.device_connection_fixture(recent, %{status: :disconnected, last_seen_at: days_ago(3)})

      for days <- [10, 20] do
        gone = device(ctx, "1.0.0", status: :provisioned)
        Fixtures.device_connection_fixture(gone, %{status: :disconnected, last_seen_at: days_ago(days)})
      end

      # connected before connection rows were kept, and never connected
      device(ctx, "1.0.0", status: :provisioned)
      device(ctx, "1.0.0")

      composition = Insights.composition(ctx.product, @now)

      assert composition.active == 2
      assert composition.active_health == %{healthy: 0, warning: 0, unhealthy: 1, unknown: 1}
      assert [%{active: 2, health: %{unknown: 5}}] = composition.versions
    end

    test "orders equal-sized versions newest first and finds the newest by semantic version", ctx do
      for version <- ["1.9.0", "1.10.0", "1.2.0", "1.2.0"], do: device(ctx, version)

      composition = Insights.composition(ctx.product, @now)

      assert Enum.map(composition.versions, & &1.version) == ["1.2.0", "1.10.0", "1.9.0"]
      assert composition.newest_version == "1.10.0"
    end

    test "leaves out soft-deleted devices", ctx do
      device(ctx, "1.0.0")

      ctx
      |> device("1.0.0")
      |> Ecto.Changeset.change(deleted_at: DateTime.truncate(@now, :second))
      |> Repo.update!()

      composition = Insights.composition(ctx.product, @now)

      assert composition.total == 1
      assert [%{version: "1.0.0", count: 1}] = composition.versions
    end

    test "only counts the product's own devices", ctx do
      device(ctx, "1.0.0")

      other = Fixtures.product_fixture(ctx.user, ctx.org, %{name: "Other"})
      assert Insights.composition(other, @now).total == 0
    end
  end

  describe "versions/1" do
    test "names every version when there are four or fewer" do
      composition = composition_of(for n <- 4..1//-1, do: {"1.#{n}.0", n, healthy: n})

      assert composition |> Insights.versions() |> Enum.map(& &1.version) ==
               ["1.4.0", "1.3.0", "1.2.0", "1.1.0"]
    end

    test "names a fifth version rather than folding it on its own" do
      composition = composition_of(for n <- 5..1//-1, do: {"1.#{n}.0", n, healthy: n})

      rows = Insights.versions(composition)

      assert length(rows) == 5
      assert Enum.all?(rows, &(&1.kind == :version))
    end

    test "folds everything past the fourth version into one row" do
      composition =
        composition_of([
          {"1.7.0", 7, healthy: 7},
          {"1.6.0", 6, healthy: 6},
          {"1.5.0", 5, healthy: 5},
          {"1.4.0", 4, healthy: 4},
          {"1.3.0", 3, healthy: 3},
          {"1.2.0", 2, healthy: 1, warning: 1},
          {"1.1.0", 1, unhealthy: 1}
        ])

      assert %{
               kind: :others,
               version: nil,
               folded: 3,
               count: 6,
               health: %{healthy: 4, warning: 1, unhealthy: 1, unknown: 0},
               offline: 6,
               active: 6,
               active_health: %{healthy: 4, warning: 1, unhealthy: 1, unknown: 0}
             } = composition |> Insights.versions() |> List.last()
    end

    test "marks the devices with no version as unknown" do
      composition = composition_of([{"1.0.0", 2, healthy: 2}, {nil, 1, unknown: 1}])

      assert [%{kind: :version}, %{kind: :unknown, version: nil}] = Insights.versions(composition)
    end
  end

  describe "stands_out/1" do
    test "says nothing for a product with no devices" do
      assert Insights.stands_out(composition_of([])) == nil
    end

    test "has nothing to compare when every device is on one version" do
      composition = composition_of([{"1.0.0", 20, healthy: 15, warning: 5}])

      assert %{kind: :single, row: %{version: "1.0.0"}, not_healthy: 5, active: 20} =
               Insights.stands_out(composition)
    end

    test "says every device is healthy" do
      composition = composition_of([{"2.0.0", 20, healthy: 20}, {"1.0.0", 10, healthy: 10}])

      assert %{kind: :all_healthy, active: 30, offline: 30} = Insights.stands_out(composition)
    end

    test "says every device is healthy when only devices that are gone aren't" do
      composition = composition_of([{"2.0.0", 20, [healthy: 20]}, {"1.0.0", 10, [unknown: 10], []}])

      assert %{kind: :all_healthy, active: 20} = Insights.stands_out(composition)
    end

    test "has nothing to judge when no device was seen in the last 7 days" do
      composition = composition_of([{"2.0.0", 20, [healthy: 20], []}, {"1.0.0", 10, [unknown: 10], []}])

      assert Insights.stands_out(composition) == %{kind: :inactive, total: 30}
    end

    test "names a version with at least twice the fleet's share of devices that aren't healthy" do
      # fleet: 22 of 160 not healthy (13.75%); 1.0.0: 17 of 40 (42.5%)
      composition =
        composition_of([
          {"2.0.0", 120, healthy: 115, warning: 5},
          {"1.0.0", 40, healthy: 23, warning: 9, unhealthy: 4, unknown: 4}
        ])

      assert %{kind: :version, row: %{version: "1.0.0"}, rate: 0.425, not_healthy: 22, active: 160} =
               Insights.stands_out(composition)
    end

    test "judges health on devices seen in the last 7 days, not ones that are gone" do
      # 0.25.1's 75 devices were all last seen weeks ago, and never reported health
      composition =
        composition_of([
          {"0.29.0", 100, [healthy: 97, unhealthy: 3]},
          {"0.25.1", 75, [unknown: 75], []}
        ])

      assert %{kind: :even, fleet_rate: 0.03, not_healthy: 3, active: 100, rows: rows} =
               Insights.stands_out(composition)

      assert [0.03, nil] = Enum.map(rows, &Insights.rate/1)
    end

    test "names the worst of several versions that stand out" do
      composition =
        composition_of([
          {"3.0.0", 200, healthy: 200},
          {"2.0.0", 20, healthy: 14, warning: 6},
          {"1.0.0", 10, healthy: 5, unhealthy: 5}
        ])

      assert %{kind: :version, row: %{version: "1.0.0"}} = Insights.stands_out(composition)
    end

    test "ignores a version with fewer than ten devices" do
      composition = composition_of([{"2.0.0", 100, healthy: 95, warning: 5}, {"1.0.0", 9, unhealthy: 9}])

      assert %{kind: :even, fleet_rate: fleet_rate, not_healthy: 14, min_devices: 10} = Insights.stands_out(composition)
      assert_in_delta fleet_rate, 14 / 109, 0.0001
    end

    test "ignores a version with fewer than three devices that aren't healthy" do
      # the fleet is 0.2% not healthy, so twice that is a single device
      two = composition_of([{"2.0.0", 990, healthy: 990}, {"1.0.0", 12, healthy: 10, unhealthy: 2}])
      three = composition_of([{"2.0.0", 990, healthy: 990}, {"1.0.0", 12, healthy: 9, unhealthy: 3}])

      assert %{kind: :even, min_not_healthy: 3} = Insights.stands_out(two)
      assert %{kind: :version, row: %{version: "1.0.0"}} = Insights.stands_out(three)
    end

    test "never names the devices with no version or the folded others" do
      composition =
        composition_of([
          {"1.5.0", 100, healthy: 100},
          {"1.4.0", 90, healthy: 90},
          {"1.3.0", 80, healthy: 80},
          {nil, 20, unknown: 20},
          {"1.2.0", 70, healthy: 70},
          {"1.1.0", 60, healthy: 60},
          {"1.0.0", 15, unhealthy: 15}
        ])

      assert %{kind: :even, rows: rows} = Insights.stands_out(composition)
      assert [:unknown, :others] = rows |> Enum.drop(3) |> Enum.map(& &1.kind)
    end

    test "says nothing stands out when versions are about as healthy as each other" do
      composition =
        composition_of([{"2.0.0", 100, healthy: 90, warning: 10}, {"1.0.0", 50, healthy: 44, warning: 6}])

      assert %{kind: :even, rows: [%{version: "2.0.0"}, %{version: "1.0.0"}]} = Insights.stands_out(composition)
    end
  end

  # A device reporting `version`, or no firmware at all when it's nil.
  defp device(%{org: org, product: product, firmware: firmware}, version, params \\ []) do
    {:ok, metadata} = Firmwares.metadata_from_firmware(firmware)
    firmware_metadata = if version, do: %{metadata | version: version}

    Fixtures.device_fixture(
      org,
      product,
      firmware,
      params |> Map.new() |> Map.put(:firmware_metadata, firmware_metadata)
    )
  end

  defp set_health(device, status) do
    {:ok, _} =
      Health.save_device_health(%{
        "device_id" => device.id,
        "data" => %{},
        "status" => status,
        "status_reasons" => %{}
      })
  end

  defp days_ago(days), do: DateTime.add(@now, -days, :day)

  # A composition as `Insights.composition/2` returns it, from
  # `{version, count, health}` or `{version, count, health, active_health}` in
  # the order given. Every device is offline. With no `active_health` every
  # device was seen in the last 7 days; with one, only those it counts were,
  # and the rest weren't seen in 14 days.
  defp composition_of(versions) do
    no_health = %{healthy: 0, warning: 0, unhealthy: 0, unknown: 0}

    versions =
      Enum.map(versions, fn
        {version, count, health} ->
          health = Map.merge(no_health, Map.new(health))
          %{version: version, count: count, health: health, offline: count, active: count, active_health: health}

        {version, count, health, active_health} ->
          active_health = Map.merge(no_health, Map.new(active_health))

          %{
            version: version,
            count: count,
            health: Map.merge(no_health, Map.new(health)),
            offline: count,
            active: active_health |> Map.values() |> Enum.sum(),
            active_health: active_health
          }
      end)

    total = Enum.sum_by(versions, & &1.count)
    active = Enum.sum_by(versions, & &1.active)

    %{
      total: total,
      connection: %{online: 0, recent: active, week: 0, stale: total - active, never: 0},
      health: sum_health(versions, :health),
      active: active,
      active_health: sum_health(versions, :active_health),
      versions: versions,
      newest_version: nil
    }
  end

  defp sum_health(versions, key) do
    Map.new([:healthy, :warning, :unhealthy, :unknown], fn status ->
      {status, Enum.sum_by(versions, &Map.fetch!(&1, key)[status])}
    end)
  end
end
