defmodule NervesHub.Devices.HealthEvaluationTest do
  # Not async: the disconnects tests read/write the AnalyticsRepo (ClickHouse).
  use NervesHub.DataCase, async: false

  import Ecto.Query

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.DeviceConnectionHistory
  alias NervesHub.Devices.DeviceHealth
  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.Devices.HealthEvaluation
  alias NervesHub.Devices.Metrics
  alias NervesHub.ErrorReports
  alias NervesHub.ErrorReports.ErrorReport
  alias NervesHub.ErrorReports.GroupBuffer
  alias NervesHub.Fixtures
  alias NervesHub.Products.HealthProfile
  alias NervesHub.Products.HealthProfileMetric
  alias NervesHub.Products.HealthProfiles

  setup %{tmp_dir: tmp_dir} do
    AnalyticsRepo.query!("TRUNCATE TABLE device_metrics")
    on_exit(fn -> AnalyticsRepo.query!("TRUNCATE TABLE device_metrics") end)

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

  # Readings land in ClickHouse the way production writes them: through
  # `Metrics.record/3`, flushed so the assertions don't race the buffer.
  defp insert_metric(device, key, value, minutes_ago \\ 0) do
    device_info = %DeviceInfo{
      device_id: device.id,
      device_identifier: device.identifier,
      org_id: device.org_id,
      product_id: device.product_id
    }

    {:ok, 1} = Metrics.record(device_info, %{key => value}, DateTime.add(DateTime.utc_now(), -minutes_ago, :minute))
    :ok = Buffer.flush(DeviceMetric)
  end

  # Every built-in test adds its metric to the product's default profile with
  # hour-long windows at both levels.
  defp add_built_in(product, key, warning, alert) do
    profile = HealthProfiles.resolve(product.id, nil)

    {:ok, _} =
      HealthProfiles.add_metric(profile, %{
        "key" => key,
        "warning_threshold" => to_string(warning),
        "warning_period_seconds" => "3600",
        "alert_threshold" => to_string(alert),
        "alert_period_seconds" => "3600"
      })

    :ok
  end

  # Health rows the way production leaves them: the report under `data`,
  # backdated so they land in (or out of) the window.
  defp insert_health_report(device, data, minutes_ago) do
    Repo.insert!(%DeviceHealth{
      device_id: device.id,
      data: data,
      inserted_at: DateTime.add(DateTime.utc_now(), -minutes_ago, :minute)
    })
  end

  describe "against the default profile" do
    test "no samples means no opinion", %{device_info: device_info} do
      assert {:unknown, nil} = HealthEvaluation.evaluate(device_info, [])
    end

    test "samples under every threshold are healthy", %{device: device, device_info: device_info} do
      insert_metric(device, "cpu_usage_percent", 20.0)
      insert_metric(device, "mem_used_percent", 30.0)

      assert {:healthy, nil} = HealthEvaluation.evaluate(device_info, [])
    end

    test "a warning-level majority engages warning, with the window in the reason", %{
      device: device,
      device_info: device_info
    } do
      insert_metric(device, "cpu_usage_percent", 85.0)

      assert {:warning, reasons} = HealthEvaluation.evaluate(device_info, [])
      assert reasons.unhealthy == %{}

      assert reasons.warning == %{
               "cpu_usage_percent" => %{
                 value: 100,
                 threshold: 80.0,
                 operator: :gte,
                 period_seconds: 3600,
                 aggregation: :share
               }
             }
    end

    test "an alert-level majority beats a warning elsewhere", %{device: device, device_info: device_info} do
      insert_metric(device, "cpu_usage_percent", 85.0)
      insert_metric(device, "mem_used_percent", 95.0)

      assert {:unhealthy, reasons} = HealthEvaluation.evaluate(device_info, [])
      assert %{"mem_used_percent" => %{threshold: 80.0}} = reasons.unhealthy
      assert %{"cpu_usage_percent" => _} = reasons.warning
    end

    test "a single spike is one vote among many, not a trip", %{device: device, device_info: device_info} do
      insert_metric(device, "cpu_usage_percent", 100.0, 10)
      insert_metric(device, "cpu_usage_percent", 10.0, 5)
      insert_metric(device, "cpu_usage_percent", 10.0)

      assert {:healthy, nil} = HealthEvaluation.evaluate(device_info, [])
    end

    test "one absurd glitch reading doesn't poison the window", %{device: device, device_info: device_info} do
      # A cheap temperature sensor catching interference: a mean over this
      # window would sit in the thousands for as long as the reading stays
      # in it; one vote out of three engages nothing.
      insert_metric(device, "cpu_usage_percent", 30.0, 10)
      insert_metric(device, "cpu_usage_percent", 17_000.0, 5)
      insert_metric(device, "cpu_usage_percent", 31.0)

      assert {:healthy, nil} = HealthEvaluation.evaluate(device_info, [])
    end

    test "samples outside the measurement period are ignored", %{device: device, device_info: device_info} do
      insert_metric(device, "cpu_usage_percent", 100.0, 90)
      insert_metric(device, "cpu_usage_percent", 20.0)

      assert {:healthy, nil} = HealthEvaluation.evaluate(device_info, [])
    end

    test "readings still in the write buffer are judged in hand", %{device_info: device_info} do
      # Nothing stored, nothing flushed: the sample exists only in this call.
      in_hand = [{"cpu_usage_percent", DateTime.utc_now(), 95.0}]

      assert {:unhealthy, %{unhealthy: %{"cpu_usage_percent" => %{value: 100}}}} =
               HealthEvaluation.evaluate(device_info, in_hand)
    end

    test "metrics outside the profile do not affect the status", %{device: device, device_info: device_info} do
      insert_metric(device, "my_custom_metric", 1_000_000.0)

      assert {:unknown, nil} = HealthEvaluation.evaluate(device_info, [])
    end
  end

  describe "a low-is-unhealthy metric" do
    test "a dropping frame rate engages", %{product: product, device: device, device_info: device_info} do
      {:ok, _} =
        product.id
        |> HealthProfiles.resolve(nil)
        |> HealthProfiles.add_metric(%{
          "key" => "fps",
          "operator" => "lte",
          "warning_threshold" => "25",
          "warning_period_seconds" => "3600",
          "alert_threshold" => "15",
          "alert_period_seconds" => "3600"
        })

      insert_metric(device, "fps", 12.0)

      assert {:unhealthy, reasons} = HealthEvaluation.evaluate(device_info, [])
      assert %{"fps" => %{threshold: 15.0, operator: :lte}} = reasons.unhealthy
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

      assert {:unhealthy, reasons} = HealthEvaluation.evaluate(device_info, [])
      assert %{"cpu_usage_percent" => %{threshold: 15.0}} = reasons.unhealthy
    end

    test "without ClickHouse there is no history to window: legacy check on the report", %{
      device: device,
      device_info: device_info
    } do
      insert_metric(device, "cpu_usage_percent", 20.0)

      original = Application.get_env(:nerves_hub, :analytics_enabled)
      Application.put_env(:nerves_hub, :analytics_enabled, false)
      on_exit(fn -> Application.put_env(:nerves_hub, :analytics_enabled, original) end)

      # The stored low readings are invisible; only the report is judged.
      assert {:unhealthy, reasons} =
               HealthEvaluation.evaluate(device_info, [{"cpu_usage_percent", DateTime.utc_now(), 95}])

      assert %{"cpu_usage_percent" => %{value: 95, threshold: 90}} = reasons.unhealthy
    end

    test "a product without any profile falls back to the legacy instantaneous check", %{device_info: device_info} do
      Repo.delete_all(HealthProfile)

      assert {:unhealthy, reasons} =
               HealthEvaluation.evaluate(device_info, [{"cpu_usage_percent", DateTime.utc_now(), 95}])

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

      assert {:warning, reasons} = HealthEvaluation.evaluate(device_info, [])

      assert reasons.warning == %{
               "disconnects" => %{value: 4, threshold: 3.0, period_seconds: 3600, aggregation: :count}
             }

      insert_disconnects(device, 2, 10)

      assert {:unhealthy, reasons} = HealthEvaluation.evaluate(device_info, [])
      assert %{"disconnects" => %{value: 6}} = reasons.unhealthy
    end

    test "disconnects outside the window are ignored", %{device: device, device_info: device_info} do
      insert_disconnects(device, 10, 90)

      # Zero disconnects in the window is a real observation, so the metric
      # counts as healthy rather than as having no opinion.
      assert {:healthy, nil} = HealthEvaluation.evaluate(device_info, [])
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
      assert {:healthy, nil} = HealthEvaluation.evaluate(device_info, [])
    end
  end

  describe "the error_reports built-in" do
    setup %{product: product, device_info: device_info} do
      AnalyticsRepo.query!("TRUNCATE TABLE device_error_reports")
      on_exit(fn -> AnalyticsRepo.query!("TRUNCATE TABLE device_error_reports") end)

      add_built_in(product, "error_reports", 3, 5)

      %{device_info: Map.put(device_info, :allowed_extensions, [:health, :error_reports])}
    end

    defp insert_error_reports(device, count, minutes_ago \\ 5) do
      device_info = %DeviceInfo{
        device_id: device.id,
        device_identifier: device.identifier,
        org_id: device.org_id,
        product_id: device.product_id
      }

      at = DateTime.add(DateTime.utc_now(), -minutes_ago, :minute)

      for _ <- 1..count do
        {:ok, _} =
          ErrorReports.record(device_info, %{
            "timestamp" => DateTime.to_iso8601(at),
            "kind" => "error",
            "reason" => "** (RuntimeError) boom",
            "frames" => [%{"module" => "MyApp.Worker", "function" => "run/0", "file" => "w.ex", "line" => 3}]
          })
      end

      :ok = Buffer.flush(ErrorReport)
      :ok = GroupBuffer.flush()
    end

    test "a device without the extension gets no opinion, not a clean bill", %{device: device, device_info: device_info} do
      insert_error_reports(device, 10)

      assert {:unknown, nil} = HealthEvaluation.evaluate(Map.delete(device_info, :allowed_extensions), [])
    end

    test "enough reports in the window engage the levels", %{device: device, device_info: device_info} do
      insert_error_reports(device, 4)

      assert {:warning, reasons} = HealthEvaluation.evaluate(device_info, [])

      assert reasons.warning == %{
               "error_reports" => %{value: 4, threshold: 3.0, period_seconds: 3600, aggregation: :count}
             }

      insert_error_reports(device, 2, 10)

      assert {:unhealthy, reasons} = HealthEvaluation.evaluate(device_info, [])
      assert %{"error_reports" => %{value: 6}} = reasons.unhealthy
    end

    test "reports outside the window are ignored", %{device: device, device_info: device_info} do
      insert_error_reports(device, 10, 90)

      assert {:healthy, nil} = HealthEvaluation.evaluate(device_info, [])
    end
  end

  describe "the alarms built-in" do
    setup %{product: product} do
      add_built_in(product, "alarms", 1, 2)
    end

    test "the report in hand is judged, and on its own it is the whole window", %{device_info: device_info} do
      report = %{"alarms" => %{"disk_almost_full" => "/root"}}

      assert {:warning, reasons} = HealthEvaluation.evaluate(device_info, [], report)

      assert reasons.warning == %{
               "alarms" => %{value: 100, threshold: 1.0, operator: :gte, period_seconds: 3600, aggregation: :share}
             }
    end

    test "readings without a report are judged on the stored reports alone", %{device: device, device_info: device_info} do
      for minutes_ago <- [10, 20], do: insert_health_report(device, %{"alarms" => %{"x" => "y"}}, minutes_ago)

      assert {:warning, %{warning: %{"alarms" => %{value: 100}}}} = HealthEvaluation.evaluate(device_info, [])
    end

    test "an alarm-free stretch outvotes one alarming report", %{device: device, device_info: device_info} do
      for minutes_ago <- [10, 20, 30], do: insert_health_report(device, %{"alarms" => %{}}, minutes_ago)

      report = %{"alarms" => %{"disk_almost_full" => "/root"}}

      assert {:healthy, nil} = HealthEvaluation.evaluate(device_info, [], report)
    end

    test "two alarms for most of the window is unhealthy", %{device: device, device_info: device_info} do
      alarms = %{"disk_almost_full" => "/root", "network_down" => "eth0"}
      for minutes_ago <- [10, 20], do: insert_health_report(device, %{"alarms" => alarms}, minutes_ago)

      assert {:unhealthy, reasons} = HealthEvaluation.evaluate(device_info, [], %{"alarms" => alarms})
      assert %{"alarms" => %{value: 100, threshold: 2.0}} = reasons.unhealthy
    end

    test "reports older than the period do not count", %{device: device, device_info: device_info} do
      for minutes_ago <- [70, 80, 90, 100], do: insert_health_report(device, %{"alarms" => %{"x" => "y"}}, minutes_ago)

      assert {:healthy, nil} = HealthEvaluation.evaluate(device_info, [], %{"alarms" => %{}})
    end
  end

  describe "the failed_checks built-in" do
    setup %{product: product} do
      add_built_in(product, "failed_checks", 1, 2)
    end

    test "no checks anywhere means no opinion", %{device: device, device_info: device_info} do
      insert_health_report(device, %{"alarms" => %{}}, 5)

      assert {:unknown, nil} = HealthEvaluation.evaluate(device_info, [], %{"alarms" => %{}})
    end

    test "a failing check engages the warning", %{device_info: device_info} do
      report = %{
        "checks" => %{"db" => %{"pass" => false, "note" => "timeout"}, "net" => %{"pass" => true, "note" => ""}}
      }

      assert {:warning, reasons} = HealthEvaluation.evaluate(device_info, [], report)

      assert reasons.warning == %{
               "failed_checks" => %{
                 value: 100,
                 threshold: 1.0,
                 operator: :gte,
                 period_seconds: 3600,
                 aggregation: :share
               }
             }
    end

    test "reports without checks neither dilute nor count", %{device: device, device_info: device_info} do
      for minutes_ago <- [10, 20, 30], do: insert_health_report(device, %{"alarms" => %{}}, minutes_ago)

      report = %{"checks" => %{"db" => %{"pass" => false, "note" => "timeout"}}}

      assert {:warning, _reasons} = HealthEvaluation.evaluate(device_info, [], report)
    end

    test "all checks passing is healthy", %{device_info: device_info} do
      report = %{"checks" => %{"db" => %{"pass" => true, "note" => ""}}}

      assert {:healthy, nil} = HealthEvaluation.evaluate(device_info, [], report)
    end
  end

  describe "the update_attempts built-in" do
    setup %{product: product} do
      add_built_in(product, "update_attempts", 2, 4)
    end

    defp set_update_attempts(device, minutes_ago_list) do
      now = DateTime.utc_now(:second)
      attempts = Enum.map(minutes_ago_list, &DateTime.add(now, -&1, :minute))

      {1, _} =
        Device
        |> where(id: ^device.id)
        |> Repo.update_all(set: [update_attempts: attempts])

      :ok
    end

    test "attempts in the window engage the levels", %{device: device, device_info: device_info} do
      set_update_attempts(device, [5, 10])

      assert {:warning, reasons} = HealthEvaluation.evaluate(device_info, [])

      assert reasons.warning == %{
               "update_attempts" => %{value: 2, threshold: 2.0, period_seconds: 3600, aggregation: :count}
             }

      set_update_attempts(device, [5, 10, 15, 20])

      assert {:unhealthy, reasons} = HealthEvaluation.evaluate(device_info, [])
      assert %{"update_attempts" => %{value: 4}} = reasons.unhealthy
    end

    test "attempts outside the window are ignored", %{device: device, device_info: device_info} do
      set_update_attempts(device, [90, 100])

      assert {:healthy, nil} = HealthEvaluation.evaluate(device_info, [])
    end
  end
end
