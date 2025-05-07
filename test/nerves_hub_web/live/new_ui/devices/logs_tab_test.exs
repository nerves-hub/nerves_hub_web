defmodule NervesHubWeb.Live.NewUI.Devices.LogsTabTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Products.Product
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.LogLines
  alias NervesHub.Repo

  setup %{conn: conn} do
    Application.put_env(:nerves_hub, :analytics_enabled, true)

    [conn: init_test_session(conn, %{"new_ui" => true})]
  end

  test "clickhouse (analytics) isn't enabled", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    Application.put_env(:nerves_hub, :analytics_enabled, false)

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/logs")
    |> assert_has("div", text: "Analytics aren't enabled for your platform.")
    |> assert_has("div", text: "Check contact your Ops team for more information.")
  end

  test "device logs aren't enabled for the product", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    Product.changeset(product, %{"extensions" => %{"logging" => false}})
    |> Repo.update()

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/logs")
    |> assert_has("div", text: "Device logs aren't enabled for this product.")
    |> assert_has("div", text: "Please check the product settings.")
  end

  test "device logs aren't enabled for the device", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    Product.changeset(product, %{"extensions" => %{"logging" => true}})
    |> Repo.update()

    Device.changeset(device, %{"extensions" => %{"logging" => false}})
    |> Repo.update()

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/logs")
    |> assert_has("div", text: "Device logs aren't enabled.")
    |> assert_has("div", text: "Please check the device settings.")
  end

  test "no device logs have been created for the device", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    Product.changeset(product, %{"extensions" => %{"logging" => true}})
    |> Repo.update()

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/logs")
    |> assert_has("div", text: "No logs have been received yet.")
  end

  test "recent device logs are shown", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    Product.changeset(product, %{"extensions" => %{"logging" => true}})
    |> Repo.update()

    for n <- 1..5 do
      attrs = %{
        level: "info",
        timestamp: NaiveDateTime.utc_now(),
        message: "something wicked this way comes : #{n}"
      }

      LogLines.create!(device, attrs)
    end

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/logs")
    |> assert_has("div", text: "Showing the last 25 log lines.")
    |> assert_has("div", text: "something wicked this way comes : 1")
    |> assert_has("div", text: "something wicked this way comes : 2")
    |> assert_has("div", text: "something wicked this way comes : 3")
    |> assert_has("div", text: "something wicked this way comes : 4")
    |> assert_has("div", text: "something wicked this way comes : 5")
  end

  test "new log lines are prepended to the recent device logs list", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    Product.changeset(product, %{"extensions" => %{"logging" => true}})
    |> Repo.update()

    attrs = %{
      level: "info",
      timestamp: DateTime.utc_now(),
      message: "something wicked this way comes"
    }

    LogLines.create!(device, attrs)

    session =
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/logs")
      |> assert_has("div", text: "Showing the last 25 log lines.")
      |> assert_has("div", text: "something wicked this way comes")

    attrs = %{
      level: "info",
      timestamp: DateTime.utc_now(),
      message: "something wicked this way comes, again"
    }

    LogLines.create!(device, attrs)

    assert_has(session, "div", text: "something wicked this way comes, again")
  end

  test "only 25 log lines are shown", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    Product.changeset(product, %{"extensions" => %{"logging" => true}})
    |> Repo.update()

    for n <- 1..26 do
      attrs = %{
        level: "info",
        timestamp: DateTime.utc_now(),
        message: "something wicked this way comes : #{n}"
      }

      LogLines.create!(device, attrs)

      Process.sleep(50)
    end

    session =
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/logs")
      |> assert_has("div", text: "Showing the last 25 log lines.")
      |> assert_has("div", text: "something wicked this way comes : 25")
      |> assert_has("div", text: "something wicked this way comes : 2")
      |> refute_has("div", text: "something wicked this way comes : 1", exact: true)

    attrs = %{
      level: "info",
      timestamp: DateTime.utc_now(),
      message: "something wicked this way comes, again"
    }

    LogLines.create!(device, attrs)

    session
    |> assert_has("div", text: "something wicked this way comes, again")
    |> refute_has("div", text: "something wicked this way comes : 2", exact: true, timeout: 500)
  end
end
