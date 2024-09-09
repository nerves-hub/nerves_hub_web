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
    |> assert_has(".metrics-text", text: "No data for selected period")
  end

  test "Assert svg is rendered when metrics data exists", %{
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

    assert {:ok, _} = Metrics.save_metrics(device.id, metrics)

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
    |> assert_has("svg")
  end
end
