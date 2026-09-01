defmodule NervesHub.Devices.HealthEvaluatorTest do
  # Not async: the evaluator process reaches the database through the shared
  # sandbox connection, which only exists for non-async tests.
  use NervesHub.DataCase, async: false

  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.Devices.HealthEvaluator
  alias NervesHub.Fixtures
  alias NervesHub.Products.HealthProfile
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

    on_exit(fn ->
      case Registry.lookup(HealthEvaluator.Registry, product.id) do
        [{pid, _}] -> GenServer.stop(pid)
        [] -> :ok
      end
    end)

    {:ok, %{user: user, org: org, product: product, device: device, device_info: device_info}}
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

  defp evaluator(product_id) do
    [{pid, _}] = Registry.lookup(HealthEvaluator.Registry, product_id)
    pid
  end

  test "a cold device warms up from stored samples", %{device: device, device_info: device_info} do
    # Stored before the evaluator ever sees the device — as the extension
    # does, saving the report's metrics first.
    insert_metric(device, "cpu_usage_percent", 95.0)

    assert {:ok, :unhealthy, reasons} = HealthEvaluator.evaluate_report(device_info, %{"cpu_usage_percent" => 95.0})
    assert %{"cpu_usage_percent" => %{aggregation: :share, value: 100}} = reasons.unhealthy
  end

  test "a warm device is judged from memory, no stored samples needed", %{device: device, device_info: device_info} do
    # The first report follows the extension's contract: metrics saved, then
    # judged (the cold warm-up reads them back).
    insert_metric(device, "cpu_usage_percent", 20.0)
    assert {:ok, :healthy, nil} = HealthEvaluator.evaluate_report(device_info, %{"cpu_usage_percent" => 20.0})

    # The follow-ups are deliberately never written to device_metrics: only
    # the in-memory counters see them. Two highs against one low is a
    # majority.
    assert {:ok, :warning, _} = HealthEvaluator.evaluate_report(device_info, %{"cpu_usage_percent" => 85.0})
    assert {:ok, :warning, _} = HealthEvaluator.evaluate_report(device_info, %{"cpu_usage_percent" => 85.0})
  end

  test "samples aging out change the status on the tick, with a transition row", %{
    device: device,
    device_info: device_info
  } do
    insert_metric(device, "cpu_usage_percent", 95.0)

    {:ok, :unhealthy, _} = HealthEvaluator.evaluate_report(device_info, %{"cpu_usage_percent" => 95.0})

    pid = evaluator(device.product_id)
    send(pid, {:tick_at, DateTime.add(DateTime.utc_now(), 61, :minute)})
    # A call serializes behind the tick.
    _ = :sys.get_state(pid)

    device = Repo.preload(Repo.reload(device), :latest_health)
    assert device.latest_health.status == :unknown
  end

  test "forgetting a device makes the next report warm up again", %{device: device, device_info: device_info} do
    insert_metric(device, "cpu_usage_percent", 20.0)
    {:ok, :healthy, nil} = HealthEvaluator.evaluate_report(device_info, %{"cpu_usage_percent" => 20.0})

    :ok = HealthEvaluator.forget(device.product_id, device.id)

    # Warm-up reads every stored sample back: the earlier 20 and this 95.
    # One of two at or over the alert threshold is a majority.
    insert_metric(device, "cpu_usage_percent", 95.0)

    assert {:ok, :unhealthy, _} = HealthEvaluator.evaluate_report(device_info, %{"cpu_usage_percent" => 95.0})
  end

  test "a profile edit drops the windows and re-judges against new thresholds", %{
    product: product,
    device: device,
    device_info: device_info
  } do
    insert_metric(device, "cpu_usage_percent", 50.0)

    {:ok, :healthy, nil} = HealthEvaluator.evaluate_report(device_info, %{"cpu_usage_percent" => 50.0})

    profile = HealthProfiles.resolve(product.id, nil)
    cpu = Enum.find(profile.metrics, &(&1.key == "cpu_usage_percent"))
    {:ok, _} = HealthProfiles.update_metric(cpu, %{"warning_threshold" => "30", "alert_threshold" => "40"})

    # The broadcast reaches the evaluator; the next report warms up from the
    # stored samples and judges against the new thresholds.
    pid = evaluator(product.id)
    _ = :sys.get_state(pid)

    assert {:ok, :unhealthy, reasons} = HealthEvaluator.evaluate_report(device_info, %{"cpu_usage_percent" => 50.0})
    assert %{"cpu_usage_percent" => %{threshold: 40.0}} = reasons.unhealthy
  end

  test "a product with no profiles is unavailable, so callers fall back", %{device_info: device_info} do
    Repo.delete_all(HealthProfile)

    assert {:error, :unavailable} = HealthEvaluator.evaluate_report(device_info, %{"cpu_usage_percent" => 20.0})
  end

  test "the disconnects built-in still counts from ClickHouse", %{product: product, device_info: device_info} do
    profile = HealthProfiles.resolve(product.id, nil)

    {:ok, _} =
      HealthProfiles.add_metric(profile, %{
        "key" => "disconnects",
        "warning_threshold" => "1000000",
        "warning_period_seconds" => "3600",
        "alert_threshold" => "2000000",
        "alert_period_seconds" => "3600"
      })

    # Thresholds far above anything the shared ClickHouse table could hold:
    # the built-in judges :healthy, which is enough to prove it ran and
    # merged with the (empty) window judgements.
    assert {:ok, :healthy, nil} = HealthEvaluator.evaluate_report(device_info, %{})
  end
end
