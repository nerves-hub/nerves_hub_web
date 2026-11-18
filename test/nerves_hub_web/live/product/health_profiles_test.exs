defmodule NervesHubWeb.Live.Product.HealthProfilesTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  import Ecto.Query, only: [where: 2]

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Analytics.Buffer
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.DeviceHealth
  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.Devices.Metrics
  alias NervesHub.Fixtures
  alias NervesHub.Products.HealthProfiles
  alias NervesHub.Repo

  setup %{user: user, org: org, tmp_dir: tmp_dir} do
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

    {:ok, %{product: product, firmware: firmware, path: "/org/#{org.name}/#{product.name}/settings/health"}}
  end

  test "shows the default profile with its metrics", %{conn: conn, path: path} do
    conn
    |> visit(path)
    |> assert_has("h1", text: "Product settings")
    |> assert_has("#profile-name", text: "Default")
    |> assert_has("#metric-cpu_usage_percent", text: "cpu_usage_percent")
    |> assert_has("#metric-mem_used_percent", text: "mem_used_percent")
    |> assert_has("#metric-disk_used_percentage", text: "disk_used_percentage")
    |> assert_has("#profile-impact", text: "Right now")
    |> refute_has("#unsaved-changes")
  end

  test "shows the fleet's median and p95 beside metrics it has reported", %{
    conn: conn,
    path: path,
    product: product,
    firmware: firmware
  } do
    device = Fixtures.device_fixture(Repo.get!(Org, product.org_id), product, firmware)

    for value <- [10.0, 20.0, 30.0] do
      {:ok, _} = Metrics.record(device_info(device), %{"cpu_usage_percent" => value})
    end

    :ok = Buffer.flush(DeviceMetric)

    conn
    |> visit(path)
    |> assert_has("#metric-cpu_usage_percent", text: "fleet median 20")
    |> assert_has("#metric-mem_used_percent", text: "No readings yet")
  end

  test "is a tab of the product settings page", %{conn: conn, org: org, product: product, path: path} do
    conn
    |> visit("/org/#{org.name}/#{product.name}/settings")
    |> click_link("Device health")
    |> assert_path(path)
    |> assert_has("#profile-name", text: "Default")
  end

  test "the tab leads back to the general settings", %{conn: conn, org: org, product: product, path: path} do
    conn
    |> visit(path)
    |> click_link("General")
    |> assert_path("/org/#{org.name}/#{product.name}/settings")
    |> assert_has("#general-settings h2", text: "General")
  end

  describe "editing a profile" do
    test "keeps edits as a draft until saved", %{conn: conn, path: path, product: product} do
      {:ok, view, _html} = live(conn, path)
      cpu = index_of(view, "cpu_usage_percent")

      html =
        view
        |> form("#profile-metrics", %{
          "metrics" => %{
            "#{cpu}" => %{"warning_threshold" => "60", "warning_period_seconds" => "1800", "alert_threshold" => "75"}
          }
        })
        |> render_change()

      assert html =~ "1 unsaved change"
      assert html =~ "If you save"
      assert default_metric(product, "cpu_usage_percent").warning_threshold == 80.0

      html = view |> form("#profile-metrics") |> render_submit()

      assert html =~ "The Default profile was saved."
      refute has_element?(view, "#unsaved-changes")

      metric = default_metric(product, "cpu_usage_percent")
      assert metric.warning_threshold == 60.0
      assert metric.warning_period_seconds == 1800
      assert metric.alert_threshold == 75.0
    end

    test "the same number written another way isn't a change", %{conn: conn, path: path} do
      {:ok, view, _html} = live(conn, path)
      cpu = index_of(view, "cpu_usage_percent")

      view
      |> form("#profile-metrics", %{"metrics" => %{"#{cpu}" => %{"warning_threshold" => "80.0"}}})
      |> render_change()

      refute has_element?(view, "#unsaved-changes")
    end

    test "discard puts the saved profile back", %{conn: conn, path: path, product: product} do
      {:ok, view, _html} = live(conn, path)
      cpu = index_of(view, "cpu_usage_percent")

      view
      |> form("#profile-metrics", %{"metrics" => %{"#{cpu}" => %{"warning_threshold" => "10"}}})
      |> render_change()

      render_click(view, "remove-metric", %{"index" => "#{index_of(view, "mem_used_percent")}"})
      assert has_element?(view, "#unsaved-changes", "2 unsaved changes")

      render_click(view, "discard")

      refute has_element?(view, "#unsaved-changes")
      assert has_element?(view, "#metric-mem_used_percent")
      assert has_element?(view, ~s(input[name="metrics[#{cpu}][warning_threshold]"][value="80"]))
      assert default_metric(product, "cpu_usage_percent").warning_threshold == 80.0
    end

    test "adds a reported metric, flipped to low-is-unhealthy", %{
      conn: conn,
      path: path,
      product: product,
      firmware: firmware
    } do
      device = Fixtures.device_fixture(Repo.get!(Org, product.org_id), product, firmware)
      {:ok, _} = Metrics.record(device_info(device), %{"fps" => 60.0})
      :ok = Buffer.flush(DeviceMetric)

      {:ok, view, _html} = live(conn, path)

      view |> form("#profile-metrics", %{"add_key" => "fps"}) |> render_change()
      assert has_element?(view, "#metric-fps", "new")

      fps = index_of(view, "fps")
      render_click(view, "flip-operator", %{"index" => "#{fps}"})

      view
      |> form("#profile-metrics", %{
        "metrics" => %{"#{fps}" => %{"warning_threshold" => "25", "alert_threshold" => "15"}}
      })
      |> render_change()

      render_click(view, "toggle-featured", %{"index" => "#{fps}"})
      view |> form("#profile-metrics") |> render_submit()

      metric = default_metric(product, "fps")
      assert metric.operator == :lte
      assert metric.warning_threshold == 25.0
      assert metric.alert_threshold == 15.0
      assert metric.featured
      refute has_element?(view, "#metric-fps", "new")
    end

    test "saving keeps other metrics' thresholds exactly", %{conn: conn, path: path, product: product} do
      mem = default_metric(product, "mem_used_percent")
      {:ok, _} = HealthProfiles.update_metric(mem, %{"warning_threshold" => 0.00005, "alert_threshold" => 0.00007})

      {:ok, view, _html} = live(conn, path)

      view
      |> form("#profile-metrics", %{
        "metrics" => %{"#{index_of(view, "cpu_usage_percent")}" => %{"warning_threshold" => "60"}}
      })
      |> render_change()

      view |> form("#profile-metrics") |> render_submit()

      mem = default_metric(product, "mem_used_percent")
      assert {mem.warning_threshold, mem.alert_threshold} == {0.00005, 0.00007}
    end

    test "the phone's profile select won't switch away from unsaved changes", %{
      conn: conn,
      path: path,
      product: product,
      firmware: firmware
    } do
      {:ok, platform_profile} = HealthProfiles.create_platform_profile(product, firmware.platform)
      {:ok, view, _html} = live(conn, path)

      render_click(view, "remove-metric", %{"index" => "#{index_of(view, "cpu_usage_percent")}"})
      html = render_change(view, "select-profile", %{"profile" => "#{platform_profile.id}"})

      assert html =~ "Save or discard your changes before switching profiles."
      assert has_element?(view, "#profile-name", "Default")
      assert has_element?(view, "#unsaved-changes", "1 unsaved change")
      assert has_element?(view, "#select-health-profile-1")

      render_click(view, "discard")
      render_change(view, "select-profile", %{"profile" => "#{platform_profile.id}"})
      assert_patch(view, "#{path}?profile=#{platform_profile.id}")
    end

    test "adds only a metric the picker offers", %{conn: conn, path: path} do
      {:ok, view, _html} = live(conn, path)

      render_change(view, "edit", %{"add_key" => "not_reported_by_anything"})

      refute has_element?(view, "#metric-not_reported_by_anything")
      refute has_element?(view, "#unsaved-changes")
    end

    test "a profile deleted by someone else while it's edited isn't saved", %{
      conn: conn,
      path: path,
      product: product,
      firmware: firmware
    } do
      {:ok, profile} = HealthProfiles.create_platform_profile(product, firmware.platform)
      {:ok, view, _html} = live(conn, "#{path}?profile=#{profile.id}")

      render_click(view, "remove-metric", %{"index" => "#{index_of(view, "cpu_usage_percent")}"})
      {:ok, _} = HealthProfiles.delete_profile(profile)

      html = view |> form("#profile-metrics") |> render_submit()

      assert html =~ "The #{firmware.platform} profile was deleted by someone else"
      assert_patch(view, path)
      assert has_element?(view, "#profile-name", "Default")
    end

    test "adds the disconnects built-in with a day's thresholds", %{conn: conn, path: path, product: product} do
      {:ok, view, _html} = live(conn, path)

      view |> form("#profile-metrics", %{"add_key" => "disconnects"}) |> render_change()
      assert has_element?(view, "#metric-disconnects", "built-in")

      view |> form("#profile-metrics") |> render_submit()

      metric = default_metric(product, "disconnects")
      assert metric.built_in
      assert metric.operator == :gte
      assert {metric.warning_threshold, metric.alert_threshold} == {3.0, 10.0}
      assert {metric.warning_period_seconds, metric.alert_period_seconds} == {86_400, 86_400}
    end

    test "removing a metric takes effect on save", %{conn: conn, path: path, product: product} do
      {:ok, view, _html} = live(conn, path)

      render_click(view, "remove-metric", %{"index" => "#{index_of(view, "disk_used_percentage")}"})
      refute has_element?(view, "#metric-disk_used_percentage")
      assert default_metric(product, "disk_used_percentage")

      view |> form("#profile-metrics") |> render_submit()

      refute default_metric(product, "disk_used_percentage")
    end

    test "an alert threshold short of the warning saves nothing", %{conn: conn, path: path, product: product} do
      {:ok, view, _html} = live(conn, path)
      cpu = index_of(view, "cpu_usage_percent")
      mem = index_of(view, "mem_used_percent")

      view
      |> form("#profile-metrics", %{
        "metrics" => %{
          "#{cpu}" => %{"warning_threshold" => "80", "alert_threshold" => "70"},
          "#{mem}" => %{"warning_threshold" => "50"}
        }
      })
      |> render_change()

      html = view |> form("#profile-metrics") |> render_submit()

      assert html =~ "The profile wasn&#39;t saved. Check cpu_usage_percent."

      assert has_element?(
               view,
               "#metric-cpu_usage_percent",
               "Unhealthy must be at or above the warning threshold when high is unhealthy."
             )

      assert has_element?(view, "#unsaved-changes", "2 unsaved changes")
      assert default_metric(product, "cpu_usage_percent").alert_threshold == 90.0
      assert default_metric(product, "mem_used_percent").warning_threshold == 70.0
    end
  end

  describe "platform profiles" do
    test "are created from the Default profile and deleted", %{
      conn: conn,
      path: path,
      product: product,
      firmware: firmware
    } do
      {:ok, view, _html} = live(conn, path)

      view |> form("#add-platform-profile", %{"platform" => firmware.platform}) |> render_change()

      profile = HealthProfiles.resolve(product.id, firmware.platform)
      assert profile.platform == firmware.platform
      assert_patch(view, "#{path}?profile=#{profile.id}")
      assert has_element?(view, "#profile-name", firmware.platform)
      assert has_element?(view, "#metric-cpu_usage_percent")

      view |> element("#delete-profile") |> render_click()

      assert_patch(view, path)
      assert has_element?(view, "#profile-name", "Default")
      assert HealthProfiles.resolve(product.id, firmware.platform).platform == nil
    end

    test "can't be added until firmware reports a platform", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org, %{name: "NoFirmware"})

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings/health")
      |> assert_has("#add-platform-profile button[disabled]", text: "Add a platform profile")
      |> assert_has(~s(#add-platform-profile [title="No firmware uploaded to this product reports a platform yet."]))
    end

    test "can be added from a phone", %{conn: conn, path: path, product: product, firmware: firmware} do
      {:ok, view, _html} = live(conn, path)

      view |> form("#add-platform-profile-phone", %{"platform" => firmware.platform}) |> render_change()

      assert HealthProfiles.resolve(product.id, firmware.platform).platform == firmware.platform
    end

    test "each list the devices they cover", %{conn: conn, path: path, product: product, firmware: firmware} do
      org = Repo.get!(Org, product.org_id)
      Fixtures.device_fixture(org, product, firmware)
      Fixtures.device_fixture(org, product, firmware)
      {:ok, platform_profile} = HealthProfiles.create_platform_profile(product, firmware.platform)

      conn
      |> visit(path)
      |> assert_has("#profile-name", text: "Default")
      |> assert_has("#health-profile-#{platform_profile.id}", text: "2 devices")
      |> visit("#{path}?profile=#{platform_profile.id}")
      |> assert_has("#profile-name", text: firmware.platform)
      |> assert_has("p", text: "For the 2 devices whose firmware reports the #{firmware.platform} platform.")
      |> assert_has("#impact-unknown", text: "2 no data")
    end
  end

  describe "a member who can't change the profile" do
    setup %{user: user, org: org} do
      OrgUser
      |> where(user_id: ^user.id, org_id: ^org.id)
      |> Repo.update_all(set: [role: :view])

      :ok
    end

    test "sees it read-only", %{conn: conn, path: path} do
      conn
      |> visit(path)
      |> assert_has("#read-only-notice")
      |> assert_has("#metric-cpu_usage_percent")
      |> refute_has("button", text: "Save profile")
      |> refute_has("#add-platform-profile")
    end

    test "can't save", %{conn: conn, path: path, product: product} do
      {:ok, view, _html} = live(conn, path)
      Process.flag(:trap_exit, true)

      assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} =
               catch_exit(render_submit(view, "save", %{"metrics" => %{"0" => %{"warning_threshold" => "1"}}}))

      assert default_metric(product, "cpu_usage_percent").warning_threshold == 80.0
    end
  end

  describe "threshold suggestions" do
    # Quartiles land inside flat runs of the distribution (80 tens, 80
    # twenties, 40 thirties: q1 = 10, q3 = 20, IQR = 10), so the suggestion
    # is deterministic whatever interpolation ClickHouse uses. Tukey's
    # fences: gte 35 / 50, lte -5 / -20.
    defp seed_fps_history(product, firmware, days_ago) do
      device = Fixtures.device_fixture(Repo.get!(Org, product.org_id), product, firmware)
      at = DateTime.add(DateTime.utc_now(), -days_ago, :day)

      for value <- List.duplicate(10.0, 80) ++ List.duplicate(20.0, 80) ++ List.duplicate(30.0, 40) do
        {:ok, 1} = Metrics.record(device_info(device), %{"fps" => value}, at)
      end

      :ok = Buffer.flush(DeviceMetric)
    end

    test "a week of history fills a new metric with the suggestion", %{
      conn: conn,
      path: path,
      product: product,
      firmware: firmware
    } do
      seed_fps_history(product, firmware, 8)
      {:ok, view, _html} = live(conn, path)

      view |> form("#profile-metrics", %{"add_key" => "fps"}) |> render_change()
      fps = index_of(view, "fps")

      assert has_element?(view, ~s(input[name="metrics[#{fps}][warning_threshold]"][value="35"]))
      assert has_element?(view, ~s(input[name="metrics[#{fps}][alert_threshold]"][value="50"]))
      refute has_element?(view, "#metric-fps button", "Use suggested")

      # Flipped, the suggestion is the low-side fences, offered to use.
      render_click(view, "flip-operator", %{"index" => "#{fps}"})
      assert has_element?(view, "#metric-fps button", "Use suggested -5 / -20")

      view |> element("#metric-fps button", "Use suggested") |> render_click()

      assert has_element?(view, ~s(input[name="metrics[#{fps}][warning_threshold]"][value="-5"]))
      assert has_element?(view, ~s(input[name="metrics[#{fps}][alert_threshold]"][value="-20"]))
    end

    test "no suggestion before a full week has been seen", %{
      conn: conn,
      path: path,
      product: product,
      firmware: firmware
    } do
      seed_fps_history(product, firmware, 2)
      {:ok, view, _html} = live(conn, path)

      view |> form("#profile-metrics", %{"add_key" => "fps"}) |> render_change()
      fps = index_of(view, "fps")

      assert has_element?(view, "#metric-fps", "fleet median")
      assert has_element?(view, ~s(input[name="metrics[#{fps}][warning_threshold]"][value=""]))
      refute has_element?(view, "#metric-fps button", "Use suggested")
    end
  end

  describe "the impact of unsaved changes" do
    test "moves today's counts by what the edit would change", %{
      conn: conn,
      path: path,
      product: product,
      firmware: firmware
    } do
      org = Repo.get!(Org, product.org_id)
      [calm, busy] = for _ <- 1..2, do: Fixtures.device_fixture(org, product, firmware)
      {:ok, _} = Metrics.record(device_info(calm), %{"cpu_usage_percent" => 30.0})
      {:ok, _} = Metrics.record(device_info(busy), %{"cpu_usage_percent" => 60.0})
      :ok = Buffer.flush(DeviceMetric)

      # Today both are healthy.
      for device <- [calm, busy] do
        Repo.insert!(DeviceHealth.save(%{device_id: device.id, status: :healthy}))
      end

      {:ok, view, _html} = live(conn, path)
      render_async(view)
      assert has_element?(view, "#impact-healthy", "2 healthy")
      refute has_element?(view, "#impact-unknown")

      view
      |> form("#profile-metrics", %{
        "metrics" => %{"#{index_of(view, "cpu_usage_percent")}" => %{"warning_threshold" => "50"}}
      })
      |> render_change()

      render_async(view)

      # The edit would put the busy device at warning.
      assert has_element?(view, "#profile-impact", "If you save")
      assert has_element?(view, "#impact-healthy", "1 healthy")
      assert has_element?(view, "#impact-healthy", "−1")
      assert has_element?(view, "#impact-warning", "1 warning")
      assert has_element?(view, "#impact-warning", "+1")
    end
  end

  test "doesn't show the preview working while a threshold isn't a number", %{conn: conn, path: path} do
    {:ok, view, _html} = live(conn, path)
    render_async(view)

    # cpu_temp has no readings, so it's added with empty thresholds.
    view |> form("#profile-metrics", %{"add_key" => "cpu_temp"}) |> render_change()

    assert has_element?(view, "#profile-impact", "If you save")
    refute has_element?(view, ~s(#profile-impact [title="Working out what the changes would do"]))
  end

  # The position of a metric's row in the draft, which its inputs and buttons
  # are named by.
  defp index_of(view, key) do
    html = view |> element("#metric-#{key} input[name$='[warning_threshold]']") |> render()
    [_, index] = Regex.run(~r/metrics\[(\d+)\]/, html)
    String.to_integer(index)
  end

  defp default_metric(product, key) do
    product.id
    |> HealthProfiles.resolve(nil)
    |> Map.fetch!(:metrics)
    |> Enum.find(&(&1.key == key))
  end

  defp device_info(device) do
    %DeviceInfo{
      device_id: device.id,
      device_identifier: device.identifier,
      org_id: device.org_id,
      product_id: device.product_id
    }
  end
end
