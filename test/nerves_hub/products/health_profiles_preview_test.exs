defmodule NervesHub.Products.HealthProfilesPreviewTest do
  # Not async: the disconnects test truncates the ClickHouse connection
  # history.
  use NervesHub.DataCase, async: false

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.DeviceConnectionHistory
  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.Devices.HealthEvaluation
  alias NervesHub.Devices.Metrics
  alias NervesHub.Fixtures
  alias NervesHub.Products.HealthProfileMetric
  alias NervesHub.Products.HealthProfiles

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

    {:ok, %{user: user, org: org, product: product, firmware: firmware}}
  end

  test "judges each device as health evaluation would", %{user: user, org: org, product: product, firmware: firmware} do
    [healthy, warning, unhealthy, _silent] = for _ <- 1..4, do: Fixtures.device_fixture(org, product, firmware)
    report(healthy, %{"cpu_usage_percent" => 50.0})
    report(warning, %{"cpu_usage_percent" => 85.0})
    report(unhealthy, %{"cpu_usage_percent" => 95.0})

    {profile, profiles} = default_profile(product)
    cpu = %{metric(:gte, 80, 90) | key: "cpu_usage_percent"}

    assert HealthProfiles.preview_counts(product, user, profile, profiles, [cpu]) ==
             %{healthy: 1, warning: 1, unhealthy: 1, unknown: 1}

    # Each device judged on its own agrees.
    assert {:warning, _} = HealthEvaluation.evaluate(device_info(warning), [])

    # Lowering the warning threshold moves the healthy device.
    assert HealthProfiles.preview_counts(product, user, profile, profiles, [%{cpu | warning_threshold: 40.0}]) ==
             %{healthy: 0, warning: 2, unhealthy: 1, unknown: 1}
  end

  test "a low-is-unhealthy metric engages below its thresholds", %{
    user: user,
    org: org,
    product: product,
    firmware: firmware
  } do
    [smooth, choppy] = for _ <- 1..2, do: Fixtures.device_fixture(org, product, firmware)
    report(smooth, %{"fps" => 60.0})
    report(choppy, %{"fps" => 20.0})

    {profile, profiles} = default_profile(product)
    fps = %{metric(:lte, 25, 10) | key: "fps"}

    assert HealthProfiles.preview_counts(product, user, profile, profiles, [fps]) ==
             %{healthy: 1, warning: 1, unhealthy: 0, unknown: 0}
  end

  test "readings outside the window don't count", %{user: user, org: org, product: product, firmware: firmware} do
    device = Fixtures.device_fixture(org, product, firmware)
    report(device, %{"cpu_usage_percent" => 95.0}, DateTime.add(DateTime.utc_now(), -2, :hour))

    {profile, profiles} = default_profile(product)
    cpu = %{metric(:gte, 80, 90) | key: "cpu_usage_percent"}

    assert HealthProfiles.preview_counts(product, user, profile, profiles, [cpu]).unknown == 1

    day = %{cpu | warning_period_seconds: 86_400, alert_period_seconds: 86_400}
    assert HealthProfiles.preview_counts(product, user, profile, profiles, [day]).unhealthy == 1
  end

  test "counts only the devices the profile applies to", %{user: user, org: org, product: product, firmware: firmware} do
    rpi0 = Fixtures.device_fixture(org, product, firmware)
    esp32 = Fixtures.device_fixture(org, product, firmware, %{platform: "esp32"})
    report(rpi0, %{"cpu_usage_percent" => 95.0})
    report(esp32, %{"cpu_usage_percent" => 95.0})

    {:ok, _} = HealthProfiles.create_platform_profile(product, "esp32")
    {profile, profiles} = default_profile(product)
    esp32_profile = Enum.find(profiles, &(&1.platform == "esp32"))
    cpu = %{metric(:gte, 80, 90) | key: "cpu_usage_percent"}

    assert HealthProfiles.preview_counts(product, user, profile, profiles, [cpu]) ==
             %{healthy: 0, warning: 0, unhealthy: 1, unknown: 0}

    assert HealthProfiles.preview_counts(product, user, esp32_profile, profiles, [cpu]) ==
             %{healthy: 0, warning: 0, unhealthy: 1, unknown: 0}
  end

  describe "the disconnects built-in" do
    setup do
      AnalyticsRepo.query!("TRUNCATE TABLE device_connection_history")
      on_exit(fn -> AnalyticsRepo.query!("TRUNCATE TABLE device_connection_history") end)
    end

    test "judges every device, healthy until it disconnects enough", %{
      user: user,
      org: org,
      product: product,
      firmware: firmware
    } do
      [flaky, steady] = for _ <- 1..2, do: Fixtures.device_fixture(org, product, firmware)
      insert_disconnects(flaky, 4)
      insert_disconnects(steady, 1)

      {profile, profiles} = default_profile(product)
      disconnects = %{metric(:gte, 3, 10) | key: "disconnects", built_in: true}

      assert HealthProfiles.preview_counts(product, user, profile, profiles, [disconnects]) ==
               %{healthy: 1, warning: 1, unhealthy: 0, unknown: 0}

      assert Connections.fleet_disconnection_levels(org.id, product.id, disconnects) == %{flaky.id => 1}
    end
  end

  test "is nil without analytics", %{user: user, product: product} do
    Application.put_env(:nerves_hub, :analytics_enabled, false)
    on_exit(fn -> Application.put_env(:nerves_hub, :analytics_enabled, true) end)

    {profile, profiles} = default_profile(product)

    assert HealthProfiles.preview_counts(product, user, profile, profiles, profile.metrics) == nil
  end

  defp default_profile(product) do
    profiles = HealthProfiles.all_for_product(product)
    {Enum.find(profiles, &is_nil(&1.platform)), profiles}
  end

  defp metric(operator, warning, alert) do
    %HealthProfileMetric{
      built_in: false,
      operator: operator,
      warning_threshold: warning / 1,
      warning_period_seconds: 3600,
      alert_threshold: alert / 1,
      alert_period_seconds: 3600
    }
  end

  defp report(device, readings, at \\ DateTime.utc_now()) do
    {:ok, _} = Metrics.record(device_info(device), readings, at)
    :ok = Buffer.flush(DeviceMetric)
  end

  defp device_info(device) do
    %DeviceInfo{
      device_id: device.id,
      device_identifier: device.identifier,
      org_id: device.org_id,
      product_id: device.product_id
    }
  end

  # Each row gets a distinct `established_at`: the ReplacingMergeTree dedupes
  # on (org_id, product_id, device_id, established_at).
  defp insert_disconnects(device, count) do
    base = DateTime.add(DateTime.utc_now(), -5, :minute)

    for offset <- 1..count do
      {:ok, _} =
        %DeviceConnection{
          id: Ecto.UUID.generate(version: 7),
          org_id: device.org_id,
          product_id: device.product_id,
          device_id: device.id,
          established_at: DateTime.add(base, -offset, :second),
          last_seen_at: base,
          disconnected_at: base
        }
        |> DeviceConnectionHistory.from_device_connection_changeset()
        |> AnalyticsRepo.insert()
    end

    :ok
  end
end
