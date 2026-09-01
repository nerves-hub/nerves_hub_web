defmodule NervesHubWeb.Live.Product.HealthProfilesTest do
  use NervesHubWeb.ConnCase.Browser, async: false

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
          "warning_period_minutes" => "60",
          "alert_threshold" => "85",
          "alert_period_minutes" => "60",
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
    assert metric.alert_threshold == 85.0
    assert metric.featured == true
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
          "warning_period_minutes" => "60",
          "alert_threshold" => "6",
          "alert_period_minutes" => "60",
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
          "warning_period_minutes" => "180",
          "alert_threshold" => "75",
          "alert_period_minutes" => "60",
          "featured" => "false"
        }
      })
      |> Phoenix.LiveViewTest.render_submit()
    end)
    |> assert_has("div", text: "cpu_usage_percent was updated.")

    metric = NervesHub.Repo.reload(metric)
    assert metric.warning_threshold == 60.0
    assert metric.warning_period_minutes == 180
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
          "warning_period_minutes" => "60",
          "alert_threshold" => "70",
          "alert_period_minutes" => "60",
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
