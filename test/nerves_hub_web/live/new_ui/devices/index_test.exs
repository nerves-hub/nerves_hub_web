defmodule NervesHubWeb.Live.NewUI.Devices.IndexTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  alias NervesHub.DeviceEvents
  alias NervesHub.Devices
  alias NervesHub.Devices.Health
  alias NervesHub.FirmwareUpdates
  alias NervesHub.Fixtures
  alias NervesHub.Repo
  alias NervesHubWeb.Endpoint
  alias Phoenix.Socket.Broadcast

  test "shows a loading message (async loading)", %{conn: conn, fixture: fixture} do
    %{device: device, org: org, product: product} = fixture

    {:ok, lv, html} =
      conn
      |> live("/org/#{org.name}/#{product.name}/devices")

    assert html =~ "Loading..."

    assert render_async(lv) =~ device.identifier
  end

  describe "refreshing device list" do
    test "refreshes when page is visible", %{conn: conn, fixture: fixture} do
      %{device: device, org: org, product: product} = fixture

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
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
      Map.merge(context, %{
        offline_indicator: "span.bg-status-offline",
        online_indicator: "span.bg-status-online"
      })
    end

    test "connection:change", %{
      conn: conn,
      fixture: fixture,
      offline_indicator: offline_indicator,
      online_indicator: online_indicator
    } do
      %{device: device, org: org, product: product} = fixture

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has(offline_indicator, timeout: 1000)
      |> unwrap(fn view ->
        send(view.pid, %Broadcast{
          topic: "internal:device:#{device.id}",
          event: "connection:change",
          payload: %{status: "online"}
        })

        render(view)
      end)
      |> assert_has(online_indicator)
    end
  end

  describe "deployment group column" do
    test "shows the deployment group of devices assigned to one",
         %{conn: conn, fixture: fixture} do
      %{device: device, org: org, product: product, deployment_group: deployment_group} = fixture

      {:ok, _} = Devices.update_device(device, %{deployment_id: deployment_group.id})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("th", text: "Deployment group", timeout: 1000)
      |> assert_has("span", text: deployment_group.name)
    end

    test "shows no deployment group for unassigned devices",
         %{conn: conn, fixture: fixture} do
      %{device: _device, org: org, product: product, deployment_group: deployment_group} = fixture

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("th", text: "Deployment group", timeout: 1000)
      |> refute_has("span", text: deployment_group.name)
    end
  end

  describe "bulk adding devices to deployment group" do
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
      |> visit("/org/#{org.name}/#{product.name}/devices?platform=#{firmware.platform}")
      |> assert_has("div", text: "2", timeout: 1000)
      |> check("Select all devices", exact: false)
      |> assert_has("#bulk-selected", text: "2 selected")
      |> click_button("#bulk-group", "Deployment group")
      |> within("form#deployment-set", fn session ->
        session
        |> select("Set deployment group",
          option: deployment_group.name,
          exact_option: false
        )
        |> submit()
      end)
      |> assert_has("div", text: "All selected devices were added to deployment")

      assert_receive %{event: "updated"}
      assert_receive %{event: "updated"}

      assert Repo.reload(device) |> Map.get(:deployment_id)
      assert Repo.reload(device2) |> Map.get(:deployment_id)
    end
  end

  describe "filtering devices" do
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
      |> open_filters()
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
        Health.save_device_health(%{
          "device_id" => device2.id,
          "data" => %{},
          "status" => :healthy,
          "status_reasons" => %{}
        })

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: device.identifier, timeout: 1000)
      |> assert_has("a", text: device2.identifier)
      |> open_filters()
      |> pick("health_status", "unknown", "Unknown")
      # This also asserts that devices with nil health status are listed as unknown
      |> assert_has("a", text: device.identifier, timeout: 1000)
      |> refute_has("a", text: device2.identifier)
      |> unpick("health_status", "unknown", "Unknown")
      |> pick("health_status", "healthy", "Healthy")
      |> assert_has("a", text: device2.identifier, timeout: 1000)
      |> refute_has("a", text: device.identifier)
    end

    test "by tags", %{conn: conn, fixture: fixture} do
      %{
        device: device,
        org: org,
        product: product,
        firmware: firmware
      } = fixture

      device2 = Fixtures.device_fixture(org, product, firmware, %{tags: ["foo", "bar"]})

      {:ok, _} =
        Health.save_device_health(%{
          "device_id" => device2.id,
          "data" => %{},
          "status" => :healthy,
          "status_reasons" => %{}
        })

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: device.identifier, timeout: 1000)
      |> assert_has("a", text: device2.identifier)
      |> open_filters()
      |> fill_in("#filter-tags", "Tags", with: "beta")
      |> assert_has("a", text: device.identifier, timeout: 1000)
      |> refute_has("a", text: device2.identifier)
      |> fill_in("#filter-tags", "Tags", with: "foo")
      |> assert_has("a", text: device2.identifier, timeout: 1000)
      |> refute_has("a", text: device.identifier)
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
      |> open_filters()
      |> choose("Include")
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
      |> open_filters()
      |> choose("Only deleted")
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
      |> open_filters()
      |> pick("updates", "updating", "Updating")
      |> refute_has("a", text: device.identifier, timeout: 1000)

      {:ok, _inflight_update} = DeviceEvents.schedule_update(device.id, deployment_group)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> open_filters()
      |> pick("updates", "updating", "Updating")
      |> assert_has("a", text: device.identifier, timeout: 1000)

      {:ok, _device} = FirmwareUpdates.firmware_update_successful(device, device.firmware_metadata)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> open_filters()
      |> pick("updates", "updating", "Updating")
      |> refute_has("a", text: device.identifier, timeout: 1000)
    end
  end

  describe "pagination" do
    test "one page when there are fewer devices than a page holds", %{conn: conn, fixture: fixture} do
      %{
        org: org,
        product: product
      } = fixture

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("#device-pager nav", text: "1 / 1", timeout: 1000)
      |> assert_has("#device-pager button[aria-label='Previous page'][disabled]")
      |> assert_has("#device-pager button[aria-label='Next page'][disabled]")
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
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: first_device.identifier, timeout: 1000)
      |> assert_has("#device-pager-size-select option[value='25'][selected]")
      |> assert_has("#device-pager nav", text: "1 / 2")
      |> click_button("#device-pager button[aria-label='Next page']", "")
      |> refute_has("a", text: first_device.identifier, timeout: 1000)
      |> assert_has("#device-pager nav", text: "2 / 2")
      |> click_button("#device-pager button[aria-label='Previous page']", "")
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
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: first_device.identifier, timeout: 1000)
      |> assert_has("#device-pager nav", text: "1 / 3")
      |> click_button("#device-pager button[aria-label='Next page']", "")
      |> assert_has("#device-pager nav", text: "2 / 3", timeout: 1000)
      |> click_button("#device-pager button[aria-label='Next page']", "")
      |> assert_has("#device-pager nav", text: "3 / 3", timeout: 1000)
      |> refute_has("a", text: first_device.identifier)
      |> unwrap(&render_change(element(&1, "#device-pager-size"), %{"page-size" => "50"}))
      |> assert_has("#device-pager nav", text: "1 / 2", timeout: 1000)
      |> assert_has("a", text: first_device.identifier, timeout: 1000)
    end
  end

  # The Filters button shows once the list has loaded.
  defp open_filters(session) do
    session
    |> assert_has("#sidebar-filter-button", timeout: 1000)
    |> click_button("#sidebar-filter-button", "Filters")
  end

  # Turns one of a Filters panel chip's choices on or off, by its value.
  defp pick(session, key, value, label),
    do: check(session, "#filter-#{key} input[value='#{value}']", label, exact: false)

  defp unpick(session, key, value, label),
    do: uncheck(session, "#filter-#{key} input[value='#{value}']", label, exact: false)
end
