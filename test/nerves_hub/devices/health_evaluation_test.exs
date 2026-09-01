defmodule NervesHub.Devices.HealthEvaluationTest do
  # Not async: the disconnects tests read/write the AnalyticsRepo (ClickHouse).
  use NervesHub.DataCase, async: false

  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.DeviceConnectionHistory
  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.Devices.HealthEvaluation
  alias NervesHub.Devices.HealthEvaluation.Screen
  alias NervesHub.Fixtures
  alias NervesHub.Products.HealthProfile
  alias NervesHub.Products.HealthProfileMetric
  alias NervesHub.Products.HealthProfiles

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    device_info = %{
      device_id: device.id,
      product_id: device.product_id,
      org_id: device.org_id,
      firmware_metadata: device.firmware_metadata
    }

    {:ok, %{user: user, org: org, product: product, firmware: firmware, device: device, device_info: device_info}}
  end

  defp insert_metric(device, key, value, minutes_ago \\ 0) do
    {:ok, _} =
      %{
        device_id: device.id,
        key: key,
        value: value,
        inserted_at: DateTime.add(DateTime.utc_now(), -minutes_ago, :minute)
      }
      |> DeviceMetric.save_with_timestamp()
      |> Repo.insert()
  end

  describe "against the default profile" do
    test "no samples means no opinion", %{device_info: device_info} do
      assert {:unknown, nil} = HealthEvaluation.evaluate(device_info, %{})
    end

    test "averages under every threshold are healthy", %{device: device, device_info: device_info} do
      insert_metric(device, "cpu_usage_percent", 20.0)
      insert_metric(device, "mem_used_percent", 30.0)

      assert {:healthy, nil} = HealthEvaluation.evaluate(device_info, %{})
    end

    test "a warning-level median engages warning, with the window in the reason", %{
      device: device,
      device_info: device_info
    } do
      insert_metric(device, "cpu_usage_percent", 85.0)

      assert {:warning, reasons} = HealthEvaluation.evaluate(device_info, %{})
      assert reasons.unhealthy == %{}

      assert reasons.warning == %{
               "cpu_usage_percent" => %{value: 85.0, threshold: 80.0, period_seconds: 3600, aggregation: :median}
             }
    end

    test "an alert-level median beats a warning elsewhere", %{device: device, device_info: device_info} do
      insert_metric(device, "cpu_usage_percent", 85.0)
      insert_metric(device, "mem_used_percent", 95.0)

      assert {:unhealthy, reasons} = HealthEvaluation.evaluate(device_info, %{})
      assert %{"mem_used_percent" => %{value: 95.0, threshold: 80.0}} = reasons.unhealthy
      assert %{"cpu_usage_percent" => _} = reasons.warning
    end

    test "a single spike cannot trip the level: the median ignores it", %{device: device, device_info: device_info} do
      insert_metric(device, "cpu_usage_percent", 100.0, 10)
      insert_metric(device, "cpu_usage_percent", 10.0, 5)
      insert_metric(device, "cpu_usage_percent", 10.0)

      assert {:healthy, nil} = HealthEvaluation.evaluate(device_info, %{})
    end

    test "one absurd glitch reading doesn't poison the window", %{device: device, device_info: device_info} do
      # A cheap temperature sensor catching interference: a mean over this
      # window would sit in the thousands for as long as the reading stays in
      # it; the median never moves.
      insert_metric(device, "cpu_usage_percent", 30.0, 10)
      insert_metric(device, "cpu_usage_percent", 17_000.0, 5)
      insert_metric(device, "cpu_usage_percent", 31.0)

      assert {:healthy, nil} = HealthEvaluation.evaluate(device_info, %{})
    end

    test "samples outside the measurement period are ignored", %{device: device, device_info: device_info} do
      insert_metric(device, "cpu_usage_percent", 100.0, 90)
      insert_metric(device, "cpu_usage_percent", 20.0)

      assert {:healthy, nil} = HealthEvaluation.evaluate(device_info, %{})
    end

    test "metrics outside the profile do not affect the status", %{device: device, device_info: device_info} do
      insert_metric(device, "my_custom_metric", 1_000_000.0)

      assert {:unknown, nil} = HealthEvaluation.evaluate(device_info, %{})
    end
  end

  describe "profile resolution" do
    test "a platform profile overrides the default for its platform", %{
      product: product,
      device: device,
      device_info: device_info
    } do
      {:ok, profile} = HealthProfiles.create_platform_profile(product, device.firmware_metadata.platform)
      cpu = Enum.find(profile.metrics, &(&1.key == "cpu_usage_percent"))
      {:ok, _} = HealthProfiles.update_metric(cpu, %{"warning_threshold" => 10, "alert_threshold" => 15})

      insert_metric(device, "cpu_usage_percent", 20.0)

      assert {:unhealthy, reasons} = HealthEvaluation.evaluate(device_info, %{})
      assert %{"cpu_usage_percent" => %{threshold: 15.0}} = reasons.unhealthy
    end

    test "a product without any profile falls back to the legacy instantaneous check", %{device_info: device_info} do
      Repo.delete_all(HealthProfile)

      assert {:unhealthy, reasons} = HealthEvaluation.evaluate(device_info, %{"cpu_usage_percent" => 95})
      assert %{"cpu_usage_percent" => %{value: 95, threshold: 90}} = reasons.unhealthy
    end
  end

  describe "the disconnects built-in" do
    setup %{product: product} do
      AnalyticsRepo.query!("TRUNCATE TABLE device_connection_history")
      on_exit(fn -> AnalyticsRepo.query!("TRUNCATE TABLE device_connection_history") end)

      profile = HealthProfiles.resolve(product.id, nil)

      {:ok, _} =
        HealthProfiles.add_metric(profile, %{
          "key" => "disconnects",
          "warning_threshold" => "3",
          "warning_period_seconds" => "3600",
          "alert_threshold" => "5",
          "alert_period_seconds" => "3600"
        })

      :ok
    end

    # Each row gets a distinct `established_at`: the ReplacingMergeTree dedupes
    # on (org_id, product_id, device_id, established_at).
    defp insert_disconnects(device, count, minutes_ago \\ 5) do
      base = DateTime.add(DateTime.utc_now(), -minutes_ago, :minute)

      for offset <- 1..count do
        connection = %DeviceConnection{
          id: UUIDv7.generate(),
          org_id: device.org_id,
          product_id: device.product_id,
          device_id: device.id,
          established_at: DateTime.add(base, -offset, :second),
          last_seen_at: base,
          disconnected_at: base
        }

        {:ok, _} =
          connection
          |> DeviceConnectionHistory.from_device_connection_changeset()
          |> AnalyticsRepo.insert()
      end

      :ok
    end

    test "enough disconnects in the window engage the levels", %{device: device, device_info: device_info} do
      insert_disconnects(device, 4)

      assert {:warning, reasons} = HealthEvaluation.evaluate(device_info, %{})

      assert reasons.warning == %{
               "disconnects" => %{value: 4, threshold: 3.0, period_seconds: 3600, aggregation: :count}
             }

      insert_disconnects(device, 2, 10)

      assert {:unhealthy, reasons} = HealthEvaluation.evaluate(device_info, %{})
      assert %{"disconnects" => %{value: 6}} = reasons.unhealthy
    end

    test "disconnects outside the window are ignored", %{device: device, device_info: device_info} do
      insert_disconnects(device, 10, 90)

      # Zero disconnects in the window is a real observation, so the metric
      # counts as healthy rather than as having no opinion.
      assert {:healthy, nil} = HealthEvaluation.evaluate(device_info, %{})
    end

    test "an unknown built-in key contributes no opinion", %{product: product, device_info: device_info} do
      profile = HealthProfiles.resolve(product.id, nil)

      # A row written by a newer release that knows more built-ins.
      %HealthProfileMetric{}
      |> HealthProfileMetric.changeset(%{
        health_profile_id: profile.id,
        key: "some_future_built_in",
        built_in: true,
        warning_threshold: 1.0,
        warning_period_seconds: 3600,
        alert_threshold: 2.0,
        alert_period_seconds: 3600
      })
      |> Repo.insert!()

      # The unknown built-in contributes nothing; the disconnects metric from
      # the setup still evaluates (zero disconnects -> healthy).
      assert {:healthy, nil} = HealthEvaluation.evaluate(device_info, %{})
    end
  end

  # A screen claiming an established all-clear streak. Tests pair it with
  # contradictory samples in the database — impossible with a truthfully
  # tracked streak — so a :healthy result proves the queries were skipped
  # and a :warning result proves they ran.
  defp established_screen(product, streak_seconds) do
    profile = HealthProfiles.resolve(product.id, nil)

    %Screen{
      last_status: :healthy,
      last_reasons: nil,
      all_clear_since: DateTime.add(DateTime.utc_now(), -streak_seconds, :second),
      profile_fingerprint: Screen.fingerprint(profile)
    }
  end

  describe "screened evaluation" do
    test "a fresh screen always evaluates", %{device: device, device_info: device_info} do
      insert_metric(device, "cpu_usage_percent", 85.0)

      assert {:warning, _, %Screen{last_status: :warning}} =
               HealthEvaluation.evaluate(device_info, %{"cpu_usage_percent" => 20.0}, Screen.new())
    end

    test "an established all-clear streak skips the window queries", %{
      product: product,
      device: device,
      device_info: device_info
    } do
      insert_metric(device, "cpu_usage_percent", 95.0)
      screen = established_screen(product, 2 * 3600)

      assert {:healthy, nil, updated} = HealthEvaluation.evaluate(device_info, %{"cpu_usage_percent" => 20.0}, screen)

      # The streak keeps its original start rather than restarting.
      assert updated.all_clear_since == screen.all_clear_since
    end

    test "a streak shorter than the longest window still evaluates", %{
      product: product,
      device: device,
      device_info: device_info
    } do
      insert_metric(device, "cpu_usage_percent", 95.0)
      screen = established_screen(product, 600)

      assert {:unhealthy, _, _} = HealthEvaluation.evaluate(device_info, %{"cpu_usage_percent" => 20.0}, screen)
    end

    test "a value at the warning threshold is not clearance", %{
      product: product,
      device: device,
      device_info: device_info
    } do
      insert_metric(device, "cpu_usage_percent", 95.0)
      screen = established_screen(product, 2 * 3600)

      assert {:unhealthy, _, updated} = HealthEvaluation.evaluate(device_info, %{"cpu_usage_percent" => 80.0}, screen)

      # And it breaks the streak.
      assert updated.all_clear_since == nil
    end

    test "a report with no profile metrics does not skip", %{
      product: product,
      device: device,
      device_info: device_info
    } do
      insert_metric(device, "cpu_usage_percent", 95.0)
      screen = established_screen(product, 2 * 3600)

      assert {:unhealthy, _, _} = HealthEvaluation.evaluate(device_info, %{"some_custom_metric" => 1.0}, screen)
    end

    test "a profile with a built-in metric never skips", %{
      product: product,
      device: device,
      device_info: device_info
    } do
      insert_metric(device, "cpu_usage_percent", 95.0)
      screen = established_screen(product, 2 * 3600)

      {:ok, _} =
        product.id
        |> HealthProfiles.resolve(nil)
        |> HealthProfiles.add_metric(%{
          "key" => "disconnects",
          "warning_threshold" => "3",
          "warning_period_seconds" => "3600",
          "alert_threshold" => "6",
          "alert_period_seconds" => "3600"
        })

      # The screen's fingerprint is stale now too, but built-in presence alone
      # must already refuse the skip. Not asserting the exact level: the
      # disconnects count comes from ClickHouse, which other suites share.
      assert {status, _, _} = HealthEvaluation.evaluate(device_info, %{"cpu_usage_percent" => 20.0}, screen)
      assert status != :healthy
    end

    test "a profile edit invalidates the streak", %{product: product, device: device, device_info: device_info} do
      insert_metric(device, "cpu_usage_percent", 95.0)
      screen = established_screen(product, 2 * 3600)

      profile = HealthProfiles.resolve(product.id, nil)
      cpu = Enum.find(profile.metrics, &(&1.key == "cpu_usage_percent"))
      {:ok, _} = HealthProfiles.update_metric(cpu, %{"warning_threshold" => "10", "alert_threshold" => "20"})

      assert {:unhealthy, _, updated} = HealthEvaluation.evaluate(device_info, %{"cpu_usage_percent" => 5.0}, screen)

      # The clear report opens a new streak against the new thresholds.
      assert updated.all_clear_since != nil
      assert updated.all_clear_since != screen.all_clear_since
      assert updated.profile_fingerprint == Screen.fingerprint(HealthProfiles.resolve(product.id, nil))
    end

    test "consecutive clear reports share one streak start", %{device: device, device_info: device_info} do
      insert_metric(device, "cpu_usage_percent", 20.0)

      {:healthy, nil, screen} = HealthEvaluation.evaluate(device_info, %{"cpu_usage_percent" => 20.0}, Screen.new())
      first_start = screen.all_clear_since
      assert first_start != nil

      {:healthy, nil, screen} = HealthEvaluation.evaluate(device_info, %{"cpu_usage_percent" => 21.0}, screen)
      assert screen.all_clear_since == first_start
    end

    test "a product without a profile falls back to legacy and never skips", %{device_info: device_info} do
      Repo.delete_all(HealthProfile)

      assert {:unhealthy, _, screen} =
               HealthEvaluation.evaluate(device_info, %{"cpu_usage_percent" => 95}, Screen.new())

      assert screen.last_status == :unhealthy
      assert screen.profile_fingerprint == nil
      assert screen.all_clear_since == nil
    end
  end
end
