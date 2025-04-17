defmodule NervesHubWeb.Live.Devices.IndexTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Devices
  alias NervesHub.Fixtures

  alias NervesHub.Repo

  alias NervesHubWeb.Endpoint

  setup %{fixture: %{device: device}} do
    Endpoint.subscribe("device:#{device.id}")
  end

  test "shows a loading message (async loading)", %{conn: conn, fixture: fixture} do
    %{device: device, org: org, product: product} = fixture

    {:ok, lv, html} = live(conn, "/org/#{org.name}/#{product.name}/devices")

    assert html =~ "Loading devices..."

    assert render_async(lv) =~ device.identifier
  end

  describe "handle_event" do
    test "filters devices by exact identifier", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div", text: "2 devices found", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> click_button("Show Filters")
      |> fill_in("ID", with: device.identifier)
      |> assert_has("div", text: "1 devices found", timeout: 1_000)
      |> assert_has("div a", text: device.identifier)
      |> refute_has("div a", text: device2.identifier)
    end

    test "filters devices by wrong identifier", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div a", text: device.identifier, timeout: 1000)
      |> assert_has("div a", text: device2.identifier)
      |> click_button("Show Filters")
      |> fill_in("ID", with: "foo")
      |> assert_has("div", text: "0 devices found", timeout: 1000)
    end

    test "filters devices by prefix identifier", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div a", text: device.identifier, timeout: 1000)
      |> click_button("Show Filters")
      |> fill_in("ID", with: "device-")
      |> assert_has("div", text: "1 devices found", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
    end

    test "filters devices by suffix identifier", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture

      "device-" <> just_the_tail = device.identifier

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div a", text: device.identifier, timeout: 1000)
      |> click_button("Show Filters")
      |> fill_in("ID", with: just_the_tail)
      |> assert_has("div", text: "1 devices found", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
    end

    test "filters devices by middle identifier", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div a", text: device.identifier, timeout: 1000)
      |> click_button("Show Filters")
      |> fill_in("ID", with: "ice-")
      |> assert_has("div", text: "1 devices found", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
    end

    test "filters devices by tag", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware, %{tags: ["filtertest"]})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div", text: "2 devices found", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> click_button("Show Filters")
      |> fill_in("Tags", with: "filtertest-noshow")
      |> assert_has("div", text: "0 devices found", timeout: 1_000)
      |> refute_has("div a", text: device2.identifier)
      |> fill_in("Tags", with: "filtertest")
      |> assert_has("div", text: "1 devices found", timeout: 1_000)
      |> assert_has("div a", text: device2.identifier)
    end

    test "filters devices by metrics", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware, %{})

      # Add metrics for device2, sleep between to secure order.
      Devices.Metrics.save_metric(%{device_id: device2.id, key: "cpu_temp", value: 36})
      :timer.sleep(100)
      Devices.Metrics.save_metric(%{device_id: device2.id, key: "cpu_temp", value: 42})
      :timer.sleep(100)
      Devices.Metrics.save_metric(%{device_id: device2.id, key: "load_1min", value: 3})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div", text: "2 devices found", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> click_button("Show Filters")
      |> select("Metrics", option: "cpu_temp")
      |> assert_has("label", text: "Operator", timeout: 1000)
      |> select("Operator", option: "Greater Than")
      |> assert_has("label", text: "Value", timeout: 1000)
      |> fill_in("Value", with: "37")
      # Show only show device2, which has a value greater than 37 on most recent cpu_temp metric.
      |> assert_has("div", text: "1 devices found", timeout: 1_000)
      |> assert_has("div a", text: device2.identifier)
      |> refute_has("div a", text: device.identifier)
      |> select("Metrics", option: "cpu_temp")
      |> assert_has("label", text: "Operator", timeout: 1000)
      |> select("Operator", option: "Less than")
      |> assert_has("label", text: "Value", timeout: 1000)
      |> fill_in("Value", with: "37")
      # Should not show any device since the query is for values less than 37
      |> assert_has("div", text: "0 devices found", timeout: 1_000)
      |> refute_has("div a", text: device2.identifier)
      |> refute_has("div a", text: device.identifier)
    end

    test "filters devices by several tags", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 =
        Fixtures.device_fixture(org, product, firmware, %{tags: ["filtertest", "testfilter"]})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div", text: "2 devices found", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> click_button("Show Filters")
      |> fill_in("Tags", with: "filtertest-noshow")
      |> assert_has("div", text: "0 devices found", timeout: 1_000)
      |> refute_has("div a", text: device2.identifier)
      |> fill_in("Tags", with: "filtertest")
      |> assert_has("div", text: "1 devices found", timeout: 1_000)
      |> assert_has("div a", text: device2.identifier)
      |> fill_in("Tags", with: "filtertest, testfilter")
      |> assert_has("div", text: "1 devices found", timeout: 1_000)
      |> assert_has("div a", text: device2.identifier)
    end

    test "filters devices with no tags", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware, %{tags: nil})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div a", text: device.identifier, timeout: 1000)
      |> assert_has("div a", text: device2.identifier)
      |> click_button("Show Filters")
      |> fill_in("Tags", with: "doesntmatter")
      |> assert_has("div", text: "0 devices found", timeout: 1000)
      |> refute_has("div a", text: device2.identifier)
    end

    test "filters devices with only untagged", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware, %{tags: nil})
      device3 = Fixtures.device_fixture(org, product, firmware, %{tags: ["foo"]})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div", text: "3 devices found", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> assert_has("div a", text: device3.identifier)
      |> click_button("Show Filters")
      |> select("Untagged", option: "Only untagged")
      |> assert_has("div", text: "1 devices found", timeout: 1000)
      |> assert_has("div a", text: device2.identifier)
      |> refute_has("div a", text: device3.identifier)
    end

    test "filters devices with alarms", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)

      device_health = %{"device_id" => device.id, "data" => %{"alarms" => %{"SomeAlarm" => []}}}
      assert {:ok, _} = NervesHub.Devices.save_device_health(device_health)

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div", text: "2 devices found", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> click_button("Show Filters")
      |> select("Alarm Status", option: "Has Alarms")
      |> assert_has("div", text: "1 devices found", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> refute_has("div a", text: device2.identifier)
    end

    test "filters devices without alarms", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)

      device_health = %{"device_id" => device.id, "data" => %{"alarms" => %{"SomeAlarm" => []}}}
      assert {:ok, _} = NervesHub.Devices.save_device_health(device_health)

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div", text: "2 devices found", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> click_button("Show Filters")
      |> select("Alarm Status", option: "No alarms")
      |> assert_has("div", text: "1 devices found", timeout: 1000)
      |> assert_has("div a", text: device2.identifier)
      |> refute_has("div a", text: device.identifier)
    end

    test "filters devices with specific alarm", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)

      alarm = "SomeAlarm"
      device_health = %{"device_id" => device.id, "data" => %{"alarms" => %{alarm => []}}}
      assert {:ok, _} = NervesHub.Devices.save_device_health(device_health)

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div", text: "2 devices found", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> click_button("Show Filters")
      |> select("Alarm", option: alarm)
      |> assert_path(device_index_path(fixture), query_params: %{alarm: alarm})
      |> assert_has("div", text: "1 devices found", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> refute_has("div a", text: device2.identifier)
    end

    test "filters devices by deployment group", %{conn: conn, fixture: fixture} do
      %{
        device: device,
        firmware: firmware,
        org: org,
        product: product,
        deployment_group: deployment_group
      } =
        fixture

      device2 = Fixtures.device_fixture(org, product, firmware)

      Repo.update!(Ecto.Changeset.change(device, deployment_id: deployment_group.id))

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div", text: "2 devices found", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> click_button("Show Filters")
      |> select("Deployment Group", option: deployment_group.name)
      |> assert_has("div", text: "1 devices found", timeout: 1_000)
      |> assert_has("div a", text: device.identifier)
      |> refute_has("div a", text: device2.identifier)
    end

    test "filters devices by no deployment", %{conn: conn, fixture: %{device: device} = fixture} do
      refute device.deployment_id

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("span", text: "Show Filters", timeout: 1000)
      |> click_button("Show Filters")
      |> select("Deployment Group", option: "All")
      |> assert_has("div", text: "1 devices found", timeout: 1000)
    end

    test "select device", %{conn: conn, fixture: fixture} do
      %{device: _device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware, %{tags: nil})
      _device3 = Fixtures.device_fixture(org, product, firmware, %{tags: ["foo"]})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div", text: "3 devices found", timeout: 1000)
      |> refute_has("div", text: "(1 selected)")
      |> check("Select device #{device2.identifier}")
      |> assert_has("div", text: "(1 selected)")
    end

    test "select/deselect all devices", %{conn: conn, fixture: fixture} do
      %{device: _device, firmware: firmware, org: org, product: product} = fixture

      _device2 = Fixtures.device_fixture(org, product, firmware, %{tags: nil})
      _device3 = Fixtures.device_fixture(org, product, firmware, %{tags: ["foo"]})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div", text: "3 devices found", timeout: 1000)
      |> check("Select all devices")
      |> assert_has("div", text: "3 devices found")
      |> assert_has("div", text: "(3 selected)")
      |> uncheck("Select all devices")
      |> assert_has("div", text: "3 devices found")
      |> refute_has("div", text: "selected)")
    end
  end

  describe "bulk actions" do
    test "changes tags", %{conn: conn, fixture: fixture} do
      %{device: device, org: org, product: product} = fixture

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("h1", text: "Devices", timeout: 1_000)
      |> assert_has("span", text: "beta")
      |> assert_has("span", text: "beta-edge")
      |> unwrap(fn view ->
        render_change(view, "select", %{"id" => device.id})
      end)
      |> fill_in("Set tag(s) to:", with: "moussaka")
      |> click_button("Set")
      |> assert_has("span", text: "moussaka", timeout: 1_000)
    end

    test "add multiple devices to deployment in old UI",
         %{conn: conn, fixture: fixture} do
      %{
        device: device,
        org: org,
        product: product,
        firmware: firmware,
        deployment_group: deployment_group
      } = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)
      Endpoint.subscribe("device:#{device2.id}")

      refute device.deployment_id
      refute device2.deployment_id

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div", text: "2 devices found", timeout: 1000)
      |> click_button("Show Filters")
      |> select("Platform", option: deployment_group.firmware.platform)
      |> assert_has("div", text: "2 devices found", timeout: 1_000)
      |> check("Select all devices")
      |> assert_has("span", text: "2 selected")
      |> select("Move device(s) to deployment group:",
        option: deployment_group.name,
        exact_option: false
      )
      |> click_button("#move-deployment-group-submit", "Move")
      |> assert_has("div", text: "2 devices added to deployment")

      assert_receive %{event: "devices/updated"}
      assert_receive %{event: "devices/updated"}

      assert Repo.reload(device) |> Map.get(:deployment_id)
      assert Repo.reload(device2) |> Map.get(:deployment_id)
    end
  end

  def device_index_path(%{org: org, product: product}) do
    ~p"/org/#{org}/#{product}/devices"
  end
end
