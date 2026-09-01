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
    |> assert_has("span", text: "zwave_rssi")
    |> assert_has("span", text: "-61.00")
    |> assert_has("span", text: "battery_pct")
    |> assert_has("span", text: "87.00")
    |> assert_has("button", text: "Rediscover")
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
    %{device: device} = fixture
    {:ok, _} = Components.update_topology(device.id, @topology)
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
