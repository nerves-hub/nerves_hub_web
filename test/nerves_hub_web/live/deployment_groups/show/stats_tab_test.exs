defmodule NervesHubWeb.Live.DeploymentGroups.Show.StatsTabTest do
  # Not async: the tab reads the AnalyticsRepo (ClickHouse), which does not
  # support concurrent writes.
  use NervesHubWeb.ConnCase.Browser, async: false
  use AssertEventually, timeout: 2000, interval: 50

  import Ecto.Query, only: [where: 2]

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices.DeviceUpdateHistory
  alias NervesHub.Devices.UpdateHistory
  alias NervesHub.Devices.UpdateStat
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHub.Repo
  alias NervesHubWeb.Components.DeploymentGroupPage.Stats

  setup context do
    # The group's first release went out a day ago, so the updates below land
    # inside its window.
    a_day_ago = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)

    DeploymentRelease
    |> where(deployment_group_id: ^context.deployment_group.id)
    |> Repo.update_all(set: [inserted_at: a_day_ago])

    AnalyticsRepo.query!("TRUNCATE TABLE device_update_history")
    on_exit(fn -> AnalyticsRepo.query!("TRUNCATE TABLE device_update_history") end)

    path =
      "/org/#{context.org.name}/#{context.product.name}/deployment_groups/#{context.deployment_group.name}/stats"

    Map.put(context, :path, path)
  end

  defp stat!(device, deployment_group, firmware, attrs \\ %{}) do
    at = attrs |> Map.get(:at, DateTime.utc_now()) |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)

    %UpdateStat{}
    |> Ecto.Changeset.change(%{
      device_id: device.id,
      product_id: device.product_id,
      deployment_id: deployment_group.id,
      type: "fwup_full",
      target_firmware_uuid: firmware.uuid,
      update_bytes: Map.get(attrs, :update_bytes, 1_000_000),
      saved_bytes: 0,
      inserted_at: at,
      updated_at: at
    })
    |> Repo.insert!()
  end

  defp record!(device, deployment_group, firmware, status, opts) do
    :ok =
      UpdateHistory.record(
        device,
        status,
        Keyword.merge([deployment_id: deployment_group.id, target_firmware_uuid: firmware.uuid], opts)
      )
  end

  defp flushed!(count) do
    :ok = Buffer.flush(DeviceUpdateHistory)
    assert_eventually(AnalyticsRepo.aggregate(DeviceUpdateHistory, :count) == count)
  end

  test "opens on the current release, with how its updates ended and what they downloaded", context do
    %{conn: conn, path: path, device: device, deployment_group: deployment_group, firmware: firmware} = context
    now = DateTime.utc_now()

    stat!(device, deployment_group, firmware)
    record!(device, deployment_group, firmware, :failed, reason: "fwup error", timestamp: DateTime.add(now, -600))
    record!(device, deployment_group, firmware, :succeeded, started_at: DateTime.add(now, -250), timestamp: now)
    flushed!(2)

    conn
    |> visit(path)
    |> assert_has("#stats-release option[selected]", text: "Release 1 · current")
    |> assert_has("[data-figure='Succeeded']", text: "50.0%", timeout: 2000)
    |> assert_has("[data-figure='Succeeded']", text: "1 of 2 attempts")
    |> assert_has("[data-figure='Failed attempts']", text: "On 1 device. 1 got it on a later try.")
    |> assert_has("[data-figure='Typical update']", text: "4m 10s")
    |> assert_has("[data-figure='Downloaded']", text: "1.0 MB")
    |> assert_has("#stats-reasons [data-reason]", text: "fwup error")
    |> assert_has("#stats-downloads li", text: "Full firmware")
    |> assert_has("#stats-sources [data-source]", text: "Unknown")
  end

  test "lists every release when asked for all of them, each opening its own", context do
    %{conn: conn, path: path, user: user, org_key: org_key, product: product, deployment_group: deployment_group} =
      context

    newer = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: context.tmp_dir})

    {:ok, _} = ManagedDeployments.create_deployment_release(deployment_group, newer, nil, user, %{}, broadcast: false)

    conn
    |> visit(path <> "?release=all")
    |> assert_has("#stats-release option[selected]", text: "All releases")
    |> assert_has("#stats-release-2", text: "Current")
    |> assert_has("#stats-release-1", text: context.firmware.version)
    |> refute_has("#stats-release-1", text: "Current")
    |> within("#stats-release-1", &click_link(&1, context.firmware.version))
    |> assert_path(URI.encode(path), query_params: %{release: "1"})
    |> assert_has("#stats-release option[selected]", text: "Release 1")
    |> assert_has("#stats-window", text: "replaced by 2.0.0")
  end

  test "switching release keeps the choice in the URL", %{conn: conn, path: path} do
    conn
    |> visit(path)
    |> select("Release", option: "All releases")
    |> assert_path(URI.encode(path), query_params: %{release: "all"})
    |> assert_has("#stats-releases")
  end

  test "an unknown release number falls back to the current release", %{conn: conn, path: path} do
    conn
    |> visit(path <> "?release=99")
    |> assert_has("#stats-release option[selected]", text: "Release 1 · current")
  end

  test "a release whose updates began before the history was kept shows a dash", context do
    %{conn: conn, path: path, device: device, deployment_group: deployment_group, firmware: firmware} = context
    now = DateTime.utc_now()

    # An update in PostgreSQL from before ClickHouse kept any, and one after.
    stat!(device, deployment_group, firmware, %{at: DateTime.add(now, -1, :hour)})
    record!(device, deployment_group, firmware, :succeeded, timestamp: now)
    flushed!(1)

    conn
    |> visit(path)
    |> assert_has("[data-figure='Failed attempts']", text: "NervesHub wasn’t keeping this yet", timeout: 2000)
    |> refute_has("#stats-attempts")
    |> visit(path <> "?release=all")
    |> assert_has("#stats-releases", text: "A dash means NervesHub wasn’t keeping that number yet", timeout: 2000)
  end

  test "says so in place of each chart while nothing has happened", %{conn: conn, path: path} do
    conn
    |> visit(path)
    |> assert_has("#stats-attempts-empty", text: "No update attempts have ended yet.", timeout: 2000)
    |> refute_has("#stats-attempts svg")
    |> assert_has("#stats-downloads-empty", text: "No devices have taken this release yet.")
    |> assert_has("#stats-reasons-empty", text: "No updates have failed.")
    |> assert_has("#stats-sources-empty", text: "No updates have ended yet.")
  end

  test "says so where the server doesn't keep update outcomes", %{conn: conn, path: path} do
    analytics_enabled = Application.get_env(:nerves_hub, :analytics_enabled)
    Application.put_env(:nerves_hub, :analytics_enabled, false)
    on_exit(fn -> Application.put_env(:nerves_hub, :analytics_enabled, analytics_enabled) end)

    conn
    |> visit(path)
    |> assert_has("[data-figure='Succeeded']", text: "This server doesn’t keep update outcomes.")
    |> assert_has("#stats-durations", text: "This server doesn’t keep update outcomes.")
  end

  describe "the numbers it writes" do
    test "durations, sizes and shares" do
      assert Stats.duration(nil) == "—"
      assert Stats.duration(45) == "45s"
      assert Stats.duration(545) == "9m 05s"
      assert Stats.duration(3900) == "1h 05m"

      assert Stats.bytes(999) == "999 B"
      assert Stats.bytes(6_100_000) == "6.1 MB"
      assert Stats.bytes(7_600_000_000) == "7.6 GB"

      assert Stats.percent(1, 0) == "—"
      assert Stats.percent(0, 3) == "0%"
      assert Stats.percent(3, 3) == "100%"
      assert Stats.percent(612, 638) == "95.9%"
      # a shortfall never rounds up to 100%
      assert Stats.percent(9999, 10_000) == "99.9%"
    end
  end
end
