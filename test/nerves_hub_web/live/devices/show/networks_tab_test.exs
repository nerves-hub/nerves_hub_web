defmodule NervesHubWeb.Live.Devices.Show.NetworksTabTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Devices
  alias NervesHub.Devices.Components
  alias NervesHub.Devices.Metrics
  alias NervesHub.Extensions.PubSub, as: ExtensionsPubSub
  alias NervesHub.Products
  alias Phoenix.Socket.Broadcast

  @topology %{
    "assemblies" => [],
    "networks" => [
      %{
        "identifier" => "zwave",
        "label" => "Z-Wave",
        "metrics" => ["zwave_rssi"],
        "peers" => [
          %{
            "identifier" => "zwave-26",
            "label" => "Motion sensor",
            "metrics" => ["battery_pct"],
            "actions" => [%{"identifier" => "rediscover", "label" => "Rediscover"}]
          }
        ]
      },
      %{
        "identifier" => "zigbee",
        "label" => "Zigbee",
        "peers" => [
          %{
            "identifier" => "leak-2878f",
            "label" => "Leak sensor 2878f",
            "metrics" => ["battery_pct_leak_sensor_2878f", "rssi_leak_sensor_2878f"]
          },
          %{
            "identifier" => "leak-91c02",
            "label" => "Leak sensor 91c02",
            "metrics" => ["battery_pct_leak_sensor_91c02", "rssi_leak_sensor_91c02"]
          }
        ]
      }
    ]
  }

  defp networks_path(fixture) do
    %{device: device, org: org, product: product} = fixture
    "/org/#{org.name}/#{product.name}/devices/#{device.identifier}/networks"
  end

  test "shows the networks and peers a device reported", %{conn: conn, fixture: fixture} do
    %{device: device} = fixture
    {:ok, _} = Components.update_topology(device.id, @topology)
    {:ok, _} = Metrics.save_metrics(device.id, %{"zwave_rssi" => -61.0, "battery_pct" => 87.0})

    conn
    |> visit(networks_path(fixture))
    |> assert_has("div", text: "Z-Wave")
    |> assert_has("span", text: "Motion sensor")
    |> assert_has("span", text: "Zwave rssi")
    |> assert_has("span", text: "-61.00")
    |> assert_has("span", text: "Battery pct")
    |> assert_has("span", text: "87.00")
    |> assert_has("button", text: "Rediscover")
    |> refute_has("span", text: "zwave_rssi")
  end

  test "trims the suffix a peer's metrics share, per peer", %{conn: conn, fixture: fixture} do
    %{device: device} = fixture
    {:ok, _} = Components.update_topology(device.id, @topology)

    {:ok, _} =
      Metrics.save_metrics(device.id, %{
        "battery_pct_leak_sensor_2878f" => 91.0,
        "rssi_leak_sensor_2878f" => -48.0,
        "battery_pct_leak_sensor_91c02" => 77.0,
        "rssi_leak_sensor_91c02" => -55.0,
        "battery_pct" => 87.0
      })

    conn
    |> visit(networks_path(fixture))
    # Both leak sensors show the bare metric names; which device they belong
    # to is what the peer box already says.
    |> assert_has("span", text: "Battery pct", count: 3)
    |> assert_has("span", text: "Rssi", count: 2)
    |> assert_has("span", text: "91.00")
    |> assert_has("span", text: "77.00")
    |> refute_has("span", text: "Battery pct leak sensor 2878f")
    |> refute_has("span", text: "Rssi leak sensor 91c02")
  end

  test "explains itself when the extension is not enabled", %{conn: conn, fixture: fixture} do
    conn
    |> visit(networks_path(fixture))
    |> assert_has("div", text: "Component reporting is not enabled for your product.")
  end

  test "explains itself when nothing has been reported yet", %{conn: conn, fixture: fixture} do
    %{device: device, product: product} = fixture
    {:ok, _} = Products.enable_extension_setting(product, "components")
    {:ok, _} = Devices.enable_extension_setting(device, "components")

    conn
    |> visit(networks_path(fixture))
    |> assert_has("div", text: "This device hasn't reported any networks.")
  end

  test "a peer action reaches the device", %{conn: conn, fixture: fixture} do
    %{device: device, product: product} = fixture
    {:ok, _} = Components.update_topology(device.id, @topology)
    {:ok, _} = Products.enable_extension_setting(product, "components")
    :ok = ExtensionsPubSub.subscribe_device(device.id)

    conn
    |> visit(networks_path(fixture))
    |> click_button("Rediscover")
    |> assert_has("div", text: ~s(Requested action "rediscover" on "zwave-26".))

    assert_receive %Broadcast{event: "components:action:run", payload: payload}
    assert payload["component"] == "zwave-26"
    assert payload["action"] == "rediscover"
  end
end
