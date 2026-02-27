defmodule NervesHubWeb.Live.Devices.IndexTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Devices
  alias NervesHub.Fixtures
  alias NervesHub.Repo
  alias NervesHubWeb.Endpoint
  alias Phoenix.Socket.Broadcast

  setup %{fixture: %{device: device}} do
    Endpoint.subscribe("device:#{device.id}")
  end

  test "shows a loading message (async loading)", %{conn: conn, fixture: fixture} do
    %{device: device, org: org, product: product} = fixture

    {:ok, lv, html} = live(conn, ~p"/org/#{org}/#{product}/devices")

    assert html =~ "Loading..."

    assert render_async(lv) =~ device.identifier
  end

  describe "refreshing device list" do
    test "refreshes when page is visible", %{conn: conn, fixture: fixture} do
      %{device: device, org: org, product: product} = fixture

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("span", text: device.firmware_metadata.version, timeout: 1000)
      |> unwrap(fn view ->
        # TODO: (nshoes)
        # The original intent of this test was to update the firmware version and allow the
        # liveview to refresh and assert on the new version. However, PhoenixTest doesn't seem
        # to trigger the `Phoenix.LiveView.handle_async/3` callback, making testing
        # the refreshed results impossible.
        #
        # As it stands, this test just makes sure there's no regression in the `refresh_device_list`
        # message handling.

        # {:ok, device} =
        #   Devices.update_device(device, %{
        #     firmware_metadata: %{Map.from_struct(device.firmware_metadata) | version: "2.0.0"}
        #   })

        send(view.pid, :refresh_device_list)

        render(view)
      end)
    end
  end

  describe "device connection status updates" do
    setup context do
      Map.merge(context, %{offline_indicator_color: "#71717A", online_indicator_color: "#10B981"})
    end

    test "connection:change", %{
      conn: conn,
      fixture: fixture,
      offline_indicator_color: offline_indicator_color,
      online_indicator_color: online_indicator_color
    } do
      %{device: device, org: org, product: product} = fixture

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("circle[fill='#{offline_indicator_color}']", timeout: 1000)
      |> unwrap(fn view ->
        send(view.pid, %Broadcast{
          topic: "device:#{device.identifier}:internal",
          event: "connection:change",
          payload: %{device_id: device.identifier, status: "online"}
        })

        render(view)
      end)
      |> assert_has("circle[fill='#{online_indicator_color}']")
    end

    test "connection:status", %{
      conn: conn,
      fixture: fixture,
      offline_indicator_color: offline_indicator_color,
      online_indicator_color: online_indicator_color
    } do
      %{device: device, org: org, product: product} = fixture

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("circle[fill='#{offline_indicator_color}']", timeout: 1000)
      |> unwrap(fn view ->
        send(view.pid, %Broadcast{
          topic: "device:#{device.identifier}:internal",
          event: "connection:status",
          payload: %{device_id: device.identifier, status: "online"}
        })

        render(view)
      end)
      |> assert_has("circle[fill='#{online_indicator_color}']")
    end
  end

  describe "filtering devices" do
    test "by exact identifier", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> click_button("button[phx-click=toggle-filters]", "Filters")
      |> fill_in("Identifier", with: device.identifier)
      |> assert_has("#device-count", text: "1", timeout: 1_000)
      |> assert_has("div a", text: device.identifier)
      |> refute_has("div a", text: device2.identifier)
    end

    test "by wrong identifier", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div a", text: device.identifier, timeout: 1000)
      |> assert_has("div a", text: device2.identifier)
      |> click_button("button[phx-click=toggle-filters]", "Filters")
      |> fill_in("Identifier", with: "foo")
      |> assert_has("#device-count", text: "0", timeout: 1000)
    end

    test "by prefix identifier", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div a", text: device.identifier, timeout: 1000)
      |> click_button("button[phx-click=toggle-filters]", "Filters")
      |> fill_in("Identifier", with: "device-")
      |> assert_has("#device-count", text: "1", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
    end

    test "by suffix identifier", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture

      "device-" <> just_the_tail = device.identifier

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div a", text: device.identifier, timeout: 1000)
      |> click_button("button[phx-click=toggle-filters]", "Filters")
      |> fill_in("Identifier", with: just_the_tail)
      |> assert_has("#device-count", text: "1", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
    end

    test "by middle identifier", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div a", text: device.identifier, timeout: 1000)
      |> click_button("button[phx-click=toggle-filters]", "Filters")
      |> fill_in("Identifier", with: "ice-")
      |> assert_has("#device-count", text: "1", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
    end

    test "by platform", %{conn: conn, fixture: fixture} do
      %{
        device: device,
        org: org,
        product: product,
        user: user
      } = fixture

      org_key = Fixtures.org_key_fixture(org, user)
      foo_firmware = Fixtures.firmware_fixture(org_key, product, %{platform: "foo"})
      device2 = Fixtures.device_fixture(org, product, foo_firmware)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: device.identifier, timeout: 1000)
      |> assert_has("a", text: device2.identifier)
      |> select("Platform", option: "foo")
      |> assert_has("a", text: device2.identifier, timeout: 1000)
      |> refute_has("a", text: device.identifier)
      |> select("Platform", option: "platform")
      |> assert_has("a", text: device.identifier, timeout: 1000)
      |> refute_has("a", text: device2.identifier)
    end

    test "by health status", %{conn: conn, fixture: fixture} do
      %{
        device: device,
        org: org,
        product: product,
        firmware: firmware
      } = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)

      {:ok, _} =
        Devices.save_device_health(%{
          "device_id" => device2.id,
          "data" => %{},
          "status" => :healthy,
          "status_reasons" => %{}
        })

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: device.identifier, timeout: 1000)
      |> assert_has("a", text: device2.identifier)
      |> select("Health Status", option: "Unknown")
      # This also asserts that devices with nil health status are listed as unknown
      |> assert_has("a", text: device.identifier, timeout: 1000)
      |> refute_has("a", text: device2.identifier)
      |> select("Health Status", option: "Healthy")
      |> assert_has("a", text: device2.identifier, timeout: 1000)
      |> refute_has("a", text: device.identifier)
    end

    test "by tag", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware, %{tags: ["filter-test"]})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> click_button("button[phx-click=toggle-filters]", "Filters")
      |> fill_in("Tags", with: "filter-test-no-show")
      |> assert_has("#device-count", text: "0", timeout: 1_000)
      |> refute_has("div a", text: device2.identifier)
      |> fill_in("Tags", with: "filter-test")
      |> assert_has("#device-count", text: "1", timeout: 1_000)
      |> assert_has("div a", text: device2.identifier)
    end

    test "by metrics", %{conn: conn, fixture: fixture} do
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
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> click_button("button[phx-click=toggle-filters]", "Filters")
      |> select("Metrics", option: "cpu_temp")
      |> assert_has("label", text: "Operator", timeout: 1000)
      |> select("Metrics Operator", option: "Greater Than")
      |> assert_has("label", text: "Metrics Value", timeout: 1000)
      |> fill_in("Metrics Value", with: "37")
      # Show only show device2, which has a value greater than 37 on most recent cpu_temp metric.
      |> assert_has("#device-count", text: "1", timeout: 1_000)
      |> assert_has("div a", text: device2.identifier)
      |> refute_has("div a", text: device.identifier)
      |> select("Metrics", option: "cpu_temp")
      |> assert_has("label", text: "Operator", timeout: 1000)
      |> select("Metrics Operator", option: "Less Than")
      |> assert_has("label", text: "Metrics Value", timeout: 1000)
      |> fill_in("Metrics Value", with: "37")
      # Should not show any device since the query is for values less than 37
      |> assert_has("#device-count", text: "0", timeout: 1_000)
      |> refute_has("div a", text: device2.identifier)
      |> refute_has("div a", text: device.identifier)
    end

    test "by several tags", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 =
        Fixtures.device_fixture(org, product, firmware, %{tags: ["filter-test", "test-filter"]})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> click_button("button[phx-click=toggle-filters]", "Filters")
      |> fill_in("Tags", with: "filter-test-no-show")
      |> assert_has("#device-count", text: "0", timeout: 1_000)
      |> refute_has("div a", text: device2.identifier)
      |> fill_in("Tags", with: "filter-test")
      |> assert_has("#device-count", text: "1", timeout: 1_000)
      |> assert_has("div a", text: device2.identifier)
      |> fill_in("Tags", with: "filter-test, test-filter")
      |> assert_has("#device-count", text: "1", timeout: 1_000)
      |> assert_has("div a", text: device2.identifier)
    end

    test "with no tags", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware, %{tags: nil})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div a", text: device.identifier, timeout: 1000)
      |> assert_has("div a", text: device2.identifier)
      |> click_button("button[phx-click=toggle-filters]", "Filters")
      |> fill_in("Tags", with: "does_not_matter")
      |> assert_has("#device-count", text: "0", timeout: 1000)
      |> refute_has("div a", text: device2.identifier)
    end

    test "with only untagged", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware, %{tags: nil})
      device3 = Fixtures.device_fixture(org, product, firmware, %{tags: ["foo"]})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "3", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> assert_has("div a", text: device3.identifier)
      |> click_button("button[phx-click=toggle-filters]", "Filters")
      |> select("Untagged", option: "Only untagged")
      |> assert_has("#device-count", text: "1", timeout: 1000)
      |> assert_has("div a", text: device2.identifier)
      |> refute_has("div a", text: device3.identifier)
    end

    test "with alarms", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)

      device_health = %{"device_id" => device.id, "data" => %{"alarms" => %{"SomeAlarm" => []}}}
      assert {:ok, _} = NervesHub.Devices.save_device_health(device_health)

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> click_button("button[phx-click=toggle-filters]", "Filters")
      |> select("Alarm Status", option: "Has Alarms")
      |> assert_has("#device-count", text: "1", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> refute_has("div a", text: device2.identifier)
    end

    test "without alarms", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)

      device_health = %{"device_id" => device.id, "data" => %{"alarms" => %{"SomeAlarm" => []}}}
      assert {:ok, _} = NervesHub.Devices.save_device_health(device_health)

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> click_button("button[phx-click=toggle-filters]", "Filters")
      |> select("Alarm Status", option: "No Alarms")
      |> assert_has("#device-count", text: "1", timeout: 1000)
      |> assert_has("div a", text: device2.identifier)
      |> refute_has("div a", text: device.identifier)
    end

    test "with specific alarm", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)

      alarm = "SomeAlarm"
      device_health = %{"device_id" => device.id, "data" => %{"alarms" => %{alarm => []}}}
      assert {:ok, _} = NervesHub.Devices.save_device_health(device_health)

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> click_button("button[phx-click=toggle-filters]", "Filters")
      |> select("Alarm", option: alarm)
      |> assert_path(device_index_path(fixture), query_params: %{alarm: alarm})
      |> assert_has("#device-count", text: "1", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> refute_has("div a", text: device2.identifier)
    end

    test "by deployment group", %{conn: conn, fixture: fixture} do
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
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> click_button("button[phx-click=toggle-filters]", "Filters")
      |> select("Deployment Group", option: deployment_group.name)
      |> assert_has("#device-count", text: "1", timeout: 1_000)
      |> assert_has("div a", text: device.identifier)
      |> refute_has("div a", text: device2.identifier)
    end

    test "by no deployment", %{conn: conn, fixture: %{device: device} = fixture} do
      refute device.deployment_id

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("button", text: "Filters", timeout: 1000)
      |> click_button("button[phx-click=toggle-filters]", "Filters")
      |> select("Deployment Group", option: "All")
      |> assert_has("#device-count", text: "1", timeout: 1000)
    end

    test "select device", %{conn: conn, fixture: fixture} do
      %{device: _device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware, %{tags: nil})
      _device3 = Fixtures.device_fixture(org, product, firmware, %{tags: ["foo"]})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "3", timeout: 1000)
      |> refute_has("h4", text: "1 device selected")
      |> check("input#checkbox-device-#{device2.id}", "")
      |> assert_has("h4", text: "1 device selected")
    end

    test "select/deselect all devices", %{conn: conn, fixture: fixture} do
      %{device: _device, firmware: firmware, org: org, product: product} = fixture

      _device2 = Fixtures.device_fixture(org, product, firmware, %{tags: nil})
      _device3 = Fixtures.device_fixture(org, product, firmware, %{tags: ["foo"]})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "3", timeout: 1000)
      |> check("Select all devices")
      |> assert_has("#device-count", text: "3")
      |> assert_has("h4", text: "3 devices selected")
      |> uncheck("Select all devices")
      |> assert_has("#device-count", text: "3")
      |> refute_has("h4", text: "devices selected")
    end

    test "excludes deleted device by default", %{
      conn: conn,
      fixture: %{device: device, org: org, product: product, firmware: firmware}
    } do
      refute device.deleted_at

      deleted_device =
        Fixtures.device_fixture(org, product, firmware, %{deleted_at: DateTime.utc_now()})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: device.identifier, timeout: 1000, exact: false)
      |> refute_has("a", text: deleted_device.identifier, timeout: 1000, exact: false)
    end

    test "filter to include deleted devices", %{
      conn: conn,
      fixture: %{device: device, org: org, product: product, firmware: firmware}
    } do
      refute device.deleted_at

      deleted_device =
        Fixtures.device_fixture(org, product, firmware, %{deleted_at: DateTime.utc_now()})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> select("Include Deleted Devices?", option: "Yes")
      |> assert_has("a", text: device.identifier, timeout: 1000, exact: false)
      |> assert_has("a", text: deleted_device.identifier, exact: false)
    end

    test "filter only deleted devices", %{
      conn: conn,
      fixture: %{device: device, org: org, product: product, firmware: firmware}
    } do
      refute device.deleted_at

      deleted_device =
        Fixtures.device_fixture(org, product, firmware, %{deleted_at: DateTime.utc_now()})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> select("Include Deleted Devices?", option: "Only deleted devices")
      |> assert_has("a", text: deleted_device.identifier, timeout: 1000, exact: false)
      |> refute_has("a", text: device.identifier, exact: false)
    end

    test "filter only updating devices", %{
      conn: conn,
      fixture: %{
        device: device,
        org: org,
        product: product,
        deployment_group: deployment_group
      }
    } do
      deployment_group = Repo.preload(deployment_group, :org)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: device.identifier, timeout: 1000)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> select("Update status", option: "Updating")
      |> refute_has("a", text: device.identifier, timeout: 1000)

      {:ok, _inflight_update} = Devices.told_to_update(device, deployment_group)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> select("Update status", option: "Updating")
      |> assert_has("a", text: device.identifier, timeout: 1000)

      {:ok, _device} = Devices.firmware_update_successful(device, device.firmware_metadata)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> select("Update status", option: "Updating")
      |> refute_has("a", text: device.identifier, timeout: 1000)
    end
  end

  describe "bulk actions" do
    test "changes tags", %{conn: conn, fixture: fixture} do
      %{device: device, org: org, product: product} = fixture

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("h1", text: "Devices", timeout: 1_000)
      |> assert_has("span", text: "beta")
      |> assert_has("span", text: "beta-edge")
      |> unwrap(fn view ->
        render_change(view, "select", %{"id" => device.id})
      end)
      |> fill_in("Set tags", with: "moussaka")
      |> click_button("Set")
      |> assert_has("span", text: "moussaka", timeout: 1_000)
    end

    test "add multiple devices to deployment in new UI",
         %{conn: conn, fixture: fixture} do
      %{
        device: device,
        org: org,
        product: product,
        firmware: firmware,
        deployment_group: deployment_group
      } = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)
      Endpoint.subscribe("device:#{device.id}")
      Endpoint.subscribe("device:#{device2.id}")

      refute device.deployment_id
      refute device2.deployment_id

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices?platform=#{deployment_group.firmware.platform}")
      |> assert_has("div", text: "2", timeout: 1000)
      |> check("Select all devices", exact: false)
      |> assert_has("div", text: "2 devices selected")
      |> within("form#deployment-move", fn session ->
        session
        |> select("Deployment Group",
          option: deployment_group.name,
          exact_option: false
        )
        |> submit()
      end)
      |> assert_has("div", text: "2 devices added to deployment")

      assert_receive %{event: "updated"}
      assert_receive %{event: "updated"}

      assert Repo.reload(device) |> Map.get(:deployment_id)
      assert Repo.reload(device2) |> Map.get(:deployment_id)
    end
  end

  describe "pagination" do
    test "no pagination when less than 25 devices", %{conn: conn, fixture: fixture} do
      %{
        org: org,
        product: product
      } = fixture

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> refute_has("button", text: "25", timeout: 1000)
    end

    test "pagination with more than 25 devices", %{conn: conn, fixture: fixture} do
      %{
        org: org,
        product: product,
        firmware: firmware
      } = fixture

      for _i <- 1..26 do
        Fixtures.device_fixture(org, product, firmware)
      end

      devices = Devices.get_devices_by_org_id_and_product_id(org.id, product.id)
      [first_device | _] = devices |> Enum.sort_by(& &1.identifier)

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("a", text: first_device.identifier, timeout: 1000)
      |> assert_has("button", text: "25", timeout: 1000)
      |> assert_has("button", text: "50", timeout: 1000)
      |> assert_has("button", text: "2", timeout: 1000)
      |> click_button("button[phx-click='paginate'][phx-value-page='2']", "2")
      |> refute_has("a", text: first_device.identifier, timeout: 1000)
      |> click_button("button[phx-click='paginate'][phx-value-page='1']", "1")
      |> assert_has("a", text: first_device.identifier, timeout: 1000)
    end

    test "pagination with more than 50 devices", %{conn: conn, fixture: fixture} do
      %{
        org: org,
        product: product,
        firmware: firmware
      } = fixture

      for _i <- 1..51 do
        Fixtures.device_fixture(org, product, firmware)
      end

      devices = Devices.get_devices_by_org_id_and_product_id(org.id, product.id)
      [first_device | _] = devices |> Enum.sort_by(& &1.identifier)

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("a", text: first_device.identifier, timeout: 1000)
      |> assert_has("button", text: "25", timeout: 1000)
      |> assert_has("button", text: "50", timeout: 1000)
      |> assert_has("button", text: "2", timeout: 1000)
      |> click_button("button[phx-click='paginate'][phx-value-page='2']", "2")
      |> refute_has("a", text: first_device.identifier, timeout: 1000)
      |> click_button("button[phx-click='paginate'][phx-value-page='3']", "3")
      |> refute_has("a", text: first_device.identifier, timeout: 1000)
    end
  end

  def device_index_path(%{org: org, product: product}) do
    ~p"/org/#{org}/#{product}/devices"
  end
end
