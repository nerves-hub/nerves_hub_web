defmodule NervesHubWeb.Devices.HealthTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Devices.Metrics

  alias NervesHubWeb.Endpoint

  setup %{fixture: %{device: device}} do
    Endpoint.subscribe("device:#{device.id}")
  end

  test "assert page render when no health exist for device", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
    |> assert_has("h1", text: "Device Health")
    |> assert_has("p", text: "No data for selected period")
  end

  test "Assert canvas is rendered when metrics data exists", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    metrics = %{
      "cpu_temp" => 41.381,
      "load_15min" => 0.06,
      "load_1min" => 0.55,
      "load_5min" => 0.15,
      "size_mb" => 7892,
      "used_mb" => 172,
      "used_percent" => 2
    }

    assert {7, nil} = Metrics.save_metrics(device.id, metrics)

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
    # Five of the default metric types are shown as charts
    |> assert_has("canvas", count: 5)
  end

  test "Custom metrics", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    assert {:ok, _} =
             Metrics.save_metric(%{device_id: device.id, key: "custom_1", value: 12})

    assert {:ok, _} =
             Metrics.save_metric(%{device_id: device.id, key: "custom_2", value: 13})

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
    |> assert_has("canvas", count: 2)
  end
end
