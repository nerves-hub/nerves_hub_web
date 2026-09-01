defmodule NervesHubWeb.Live.Product.HealthProfilesTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Accounts.Org
  alias NervesHub.Devices.Metrics
  alias NervesHub.Fixtures
  alias NervesHub.Products.HealthProfiles

  setup %{user: user, org: org, tmp_dir: tmp_dir} do
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

    {:ok, %{product: product, firmware: firmware}}
  end

  test "shows the default profile with its metrics", %{conn: conn, org: org, product: product} do
    conn
    |> visit("/org/#{org.name}/#{product.name}/settings/health")
    |> assert_has("h1", text: "Health Profiles")
    |> assert_has("div", text: "Default profile")
    |> assert_has("span", text: "cpu_usage_percent")
    |> assert_has("span", text: "mem_used_percent")
    |> assert_has("span", text: "disk_used_percentage")
  end

  test "shows the observed value range beside metrics the fleet has reported", %{
    conn: conn,
    org: org,
    product: product,
    firmware: firmware
  } do
    device = Fixtures.device_fixture(NervesHub.Repo.get!(Org, product.org_id), product, firmware)
    {:ok, _} = Metrics.save_metrics(device.id, %{"cpu_usage_percent" => 10.0, "fps" => 24.0})
    {:ok, _} = Metrics.save_metrics(device.id, %{"cpu_usage_percent" => 40.5, "fps" => 61.0})

    conn
    |> visit("/org/#{org.name}/#{product.name}/settings/health")
    # Beside the configured metric's name...
    |> assert_has("span", text: "seen 10 – 40.5")
    # ...and in the picker for a metric not yet configured.
    |> assert_has("option", text: "Fps — seen 24 – 61")
  end

  test "is linked from the product settings page", %{conn: conn, org: org, product: product} do
    conn
    |> visit("/org/#{org.name}/#{product.name}/settings")
    |> click_link("Manage health profiles")
    |> assert_path("/org/#{org.name}/#{product.name}/settings/health")
    |> assert_has("h1", text: "Health Profiles")
  end

  test "adds a metric to the default profile", %{conn: conn, org: org, product: product} do
    profile = HealthProfiles.resolve(product.id, nil)

    conn
    |> visit("/org/#{org.name}/#{product.name}/settings/health")
    |> unwrap(fn view ->
      view
      |> Phoenix.LiveViewTest.form("#add-metric-#{profile.id}", %{
        "profile_id" => to_string(profile.id),
        "metric" => %{
          "key" => "cpu_temp",
          "warning_threshold" => "70",
          "warning_period_value" => "1",
          "warning_period_unit" => "hours",
          "alert_threshold" => "85",
          "alert_period_value" => "30",
          "alert_period_unit" => "minutes",
          "featured" => "true"
        }
      })
      |> Phoenix.LiveViewTest.render_submit()
    end)
    |> assert_has("div", text: "cpu_temp was added to the profile.")

    metric =
      product.id
      |> HealthProfiles.resolve(nil)
      |> Map.fetch!(:metrics)
      |> Enum.find(&(&1.key == "cpu_temp"))

    assert metric.warning_threshold == 70.0
    assert metric.warning_period_seconds == 3600
    assert metric.alert_threshold == 85.0
    assert metric.alert_period_seconds == 1800
    assert metric.featured == true
  end

  test "adds a low-is-unhealthy metric with the operator select", %{
    conn: conn,
    org: org,
    product: product,
    firmware: firmware
  } do
    # The key picker offers reported keys; report an fps sample first.
    device = Fixtures.device_fixture(NervesHub.Repo.get!(Org, product.org_id), product, firmware)
    {:ok, _} = Metrics.save_metrics(device.id, %{"fps" => 60.0})

    profile = HealthProfiles.resolve(product.id, nil)

    conn
    |> visit("/org/#{org.name}/#{product.name}/settings/health")
    |> unwrap(fn view ->
      # Flip the add-form's operator to at-or-below, then submit; the flip is
      # page state carried by the hidden input.
      _ =
        Phoenix.LiveViewTest.render_click(view, "flip-operator", %{"target" => "new-#{profile.id}", "operator" => "gte"})

      view
      |> Phoenix.LiveViewTest.form("#add-metric-#{profile.id}", %{
        "profile_id" => to_string(profile.id),
        "metric" => %{
          "key" => "fps",
          "warning_threshold" => "25",
          "warning_period_value" => "1",
          "warning_period_unit" => "hours",
          "alert_threshold" => "15",
          "alert_period_value" => "1",
          "alert_period_unit" => "hours",
          "featured" => "false"
        }
      })
      |> Phoenix.LiveViewTest.render_submit()
    end)
    |> assert_has("div", text: "fps was added to the profile.")

    metric =
      product.id
      |> HealthProfiles.resolve(nil)
      |> Map.fetch!(:metrics)
      |> Enum.find(&(&1.key == "fps"))

    assert metric.operator == :lte
  end

  test "adding the disconnects built-in flags it", %{conn: conn, org: org, product: product} do
    profile = HealthProfiles.resolve(product.id, nil)

    conn
    |> visit("/org/#{org.name}/#{product.name}/settings/health")
    |> unwrap(fn view ->
      view
      |> Phoenix.LiveViewTest.form("#add-metric-#{profile.id}", %{
        "profile_id" => to_string(profile.id),
        "metric" => %{
          "key" => "disconnects",
          "warning_threshold" => "3",
          "warning_period_value" => "1",
          "warning_period_unit" => "hours",
          "alert_threshold" => "6",
          "alert_period_value" => "1",
          "alert_period_unit" => "hours",
          "featured" => "false"
        }
      })
      |> Phoenix.LiveViewTest.render_submit()
    end)
    |> assert_has("div", text: "disconnects was added to the profile.")
    |> assert_has("span", text: "built-in")

    metric =
      product.id
      |> HealthProfiles.resolve(nil)
      |> Map.fetch!(:metrics)
      |> Enum.find(&(&1.key == "disconnects"))

    assert metric.built_in == true
  end

  test "updates a metric's thresholds", %{conn: conn, org: org, product: product} do
    profile = HealthProfiles.resolve(product.id, nil)
    metric = Enum.find(profile.metrics, &(&1.key == "cpu_usage_percent"))

    conn
    |> visit("/org/#{org.name}/#{product.name}/settings/health")
    |> unwrap(fn view ->
      view
      |> Phoenix.LiveViewTest.form("#metric-#{metric.id}", %{
        "profile_id" => to_string(profile.id),
        "metric_id" => to_string(metric.id),
        "metric" => %{
          "warning_threshold" => "60",
          "warning_period_value" => "30",
          "warning_period_unit" => "minutes",
          "alert_threshold" => "75",
          "alert_period_value" => "1",
          "alert_period_unit" => "hours",
          "featured" => "false"
        }
      })
      |> Phoenix.LiveViewTest.render_submit()
    end)
    |> assert_has("div", text: "cpu_usage_percent was updated.")

    metric = NervesHub.Repo.reload(metric)
    assert metric.warning_threshold == 60.0
    assert metric.warning_period_seconds == 1800
    assert metric.featured == false
  end

  test "rejects an alert threshold below the warning threshold", %{conn: conn, org: org, product: product} do
    profile = HealthProfiles.resolve(product.id, nil)
    metric = Enum.find(profile.metrics, &(&1.key == "cpu_usage_percent"))

    conn
    |> visit("/org/#{org.name}/#{product.name}/settings/health")
    |> unwrap(fn view ->
      view
      |> Phoenix.LiveViewTest.form("#metric-#{metric.id}", %{
        "profile_id" => to_string(profile.id),
        "metric_id" => to_string(metric.id),
        "metric" => %{
          "warning_threshold" => "80",
          "warning_period_value" => "1",
          "warning_period_unit" => "hours",
          "alert_threshold" => "70",
          "alert_period_value" => "1",
          "alert_period_unit" => "hours",
          "featured" => "true"
        }
      })
      |> Phoenix.LiveViewTest.render_submit()
    end)
    |> assert_has("div", text: "Could not update the metric")
  end

  test "removes a metric", %{conn: conn, org: org, product: product} do
    profile = HealthProfiles.resolve(product.id, nil)
    metric = Enum.find(profile.metrics, &(&1.key == "disk_used_percentage"))

    conn
    |> visit("/org/#{org.name}/#{product.name}/settings/health")
    |> unwrap(fn view ->
      Phoenix.LiveViewTest.render_click(view, "delete-metric", %{
        "profile_id" => to_string(profile.id),
        "metric_id" => to_string(metric.id)
      })
    end)
    |> assert_has("div", text: "disk_used_percentage no longer affects health for this profile.")

    refute product.id
           |> HealthProfiles.resolve(nil)
           |> Map.fetch!(:metrics)
           |> Enum.any?(&(&1.key == "disk_used_percentage"))
  end

  test "creates and deletes a platform profile", %{conn: conn, org: org, product: product, firmware: firmware} do
    conn
    |> visit("/org/#{org.name}/#{product.name}/settings/health")
    |> unwrap(fn view ->
      view
      |> Phoenix.LiveViewTest.form("form[phx-submit=create-platform-profile]", %{"platform" => firmware.platform})
      |> Phoenix.LiveViewTest.render_submit()
    end)
    |> assert_has("div", text: "Platform: #{firmware.platform}")

    profile = HealthProfiles.resolve(product.id, firmware.platform)
    assert profile.platform == firmware.platform

    conn
    |> visit("/org/#{org.name}/#{product.name}/settings/health")
    |> unwrap(fn view ->
      Phoenix.LiveViewTest.render_click(view, "delete-profile", %{"profile_id" => to_string(profile.id)})
    end)
    |> assert_has("div", text: "health profile was deleted")

    assert HealthProfiles.resolve(product.id, firmware.platform).platform == nil
  end
end
