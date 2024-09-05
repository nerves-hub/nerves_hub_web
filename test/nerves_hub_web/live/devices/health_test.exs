defmodule NervesHubWeb.Devices.HealthTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Devices
  alias NervesHubWeb.Live.Devices.DeviceHealth

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
    device_health = %{
      "device_id" => device.id,
      "data" => %{
        "metrics" => %{
          "cpu_temp" => 41.381,
          "load_15min" => 0.06,
          "load_1min" => 0.55,
          "load_5min" => 0.15,
          "size_mb" => 7892,
          "used_mb" => 172,
          "used_percent" => 2
        },
        "timestamp" => "2024-08-26T15:44:18.295149Z"
      }
    }

    assert {:ok, %Devices.DeviceHealth{}} = Devices.save_device_health(device_health)

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
    |> assert_has("svg")
  end

  test "assert health data without metrics doesn't crash liveview", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    device_health = %{
      "device_id" => device.id,
      "data" => %{
        "timestamp" => "2024-08-26T15:44:18.295149Z"
      }
    }

    assert {:ok, %Devices.DeviceHealth{}} = Devices.save_device_health(device_health)

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
    |> assert_has(".metrics-text", text: "No data for selected period")
  end

  test "assert metrics with nil data is rejected", %{
    device: device
  } do
    valid_data = %{
      "device_id" => device.id,
      "data" => %{
        "metrics" => %{
          "cpu_temp" => 41.381,
          "load_15min" => 0.06,
          "load_1min" => 0.55,
          "load_5min" => 0.15,
          "size_mb" => 7892,
          "used_mb" => 172,
          "used_percent" => 2
        },
        "timestamp" => "2024-08-26T15:44:18.295149Z"
      }
    }

    invalid_data = %{
      "device_id" => device.id,
      "data" => %{
        "timestamp" => "2024-08-26T15:44:18.295149Z"
      }
    }

    assert {:ok, %Devices.DeviceHealth{}} = Devices.save_device_health(valid_data)
    assert {:ok, %Devices.DeviceHealth{}} = Devices.save_device_health(invalid_data)

    metrics =
      device.id
      |> Devices.get_device_health()
      |> DeviceHealth.organize_data()

    assert length(metrics.cpu_temp) == 1
  end
end
