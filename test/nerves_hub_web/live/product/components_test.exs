defmodule NervesHubWeb.Live.Product.ComponentsTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Components
  alias NervesHub.Fixtures
  alias NervesHub.Products.Product
  alias NervesHub.Repo

  setup do
    AnalyticsRepo.query!("TRUNCATE TABLE device_component_history")
    on_exit(fn -> AnalyticsRepo.query!("TRUNCATE TABLE device_component_history") end)

    :ok
  end

  defp enable(product) do
    {:ok, product} = product |> Product.changeset(%{"extensions" => %{"components" => true}}) |> Repo.update()
    product
  end

  defp sync(device, components) do
    info = %DeviceInfo{
      device_id: device.id,
      device_identifier: device.identifier,
      org_id: device.org_id,
      product_id: device.product_id
    }

    now = DateTime.utc_now()
    {:ok, entries} = Components.parse(components, now)
    :ok = Components.sync_snapshot(info, entries, now)
  end

  defp probe(serial, overrides \\ %{}) do
    Map.merge(
      %{
        "namespace" => "zigbee",
        "vendor" => "1286",
        "model" => "SNZB-02D",
        "serial" => serial,
        "vendor_name" => "Sonoff",
        "versions" => %{"firmware" => "2.1.0"}
      },
      overrides
    )
  end

  test "says how to turn components on", %{conn: conn, org: org, product: product} do
    conn
    |> visit("/org/#{org.name}/#{product.name}/components")
    |> assert_has("#components-off h2", text: "Components are off for #{product.name}")
    |> refute_has("nav a", text: "Components")
  end

  test "before any device reports", %{conn: conn, org: org, product: product} do
    product = enable(product)

    conn
    |> visit("/org/#{org.name}/#{product.name}/components")
    |> assert_has("#components-empty h2", text: "No components yet")
  end

  test "counts, and the models by namespace", %{conn: conn, org: org, product: product, device: device} = context do
    product = enable(product)
    other = Fixtures.device_fixture(org, product, context.firmware)

    sync(device, [
      probe("a"),
      probe("b", %{"reachable" => false, "versions" => %{"firmware" => "2.0.8"}}),
      %{"namespace" => "mcu", "vendor" => "raspberrypi", "model" => "rp2350", "serial" => "e6614c311b4a2c2f"}
    ])

    sync(other, [probe("c")])

    conn
    |> visit("/org/#{org.name}/#{product.name}/components")
    |> assert_has("#components-total", text: "4 components on 2 devices")
    |> assert_has("#components-working", text: "3")
    |> assert_has("#components-working", text: "75% of components")
    |> assert_has("#components-attention", text: "1 missing")
    |> assert_has("#components-models span", text: "MCU")
    |> assert_has("#components-models span", text: "Zigbee")
    |> assert_has("#components-models", text: "Sonoff SNZB-02D")
    |> assert_has("#components-models", text: "1 missing")
    |> assert_has("#components-models", text: "on 1 device")
    |> assert_has("#components-models", text: "2.1.0")
    |> assert_has("#components-models", text: "1 don't say")
  end

  test "the sidebar link carries what needs attention", %{conn: conn, org: org, product: product, device: device} do
    product = enable(product)
    sync(device, [probe("a", %{"reachable" => false})])

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices")
    |> assert_has("#nav-components", text: "1 need attention")
  end
end
