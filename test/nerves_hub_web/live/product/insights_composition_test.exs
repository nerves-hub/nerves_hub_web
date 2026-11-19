defmodule NervesHubWeb.Live.Product.InsightsCompositionTest do
  # Not async: mounting the insights page reads the AnalyticsRepo (ClickHouse).
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Devices.Health
  alias NervesHub.Firmwares
  alias NervesHub.Fixtures

  setup %{user: user, org: org, org_key: org_key, tmp_dir: tmp_dir} do
    product = Fixtures.product_fixture(user, org, %{name: "Composition"})
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

    %{product: product, firmware: firmware}
  end

  defp insights_path(org, product), do: ~p"/org/#{org}/#{product}/insights"
  defp devices_path(org, product, params), do: ~p"/org/#{org}/#{product}/devices?#{params}"

  # The active devices that aren't healthy, as the Stands out card links to them.
  @active_not_healthy ~s(health_status != "healthy" and connection != "not_seen" and not last_seen < "7 days ago")

  # `count` devices reporting `version` (no firmware at all when it's nil),
  # each with `health`. They have never connected.
  defp devices_on(%{org: org, product: product, firmware: firmware}, version, count, health \\ :healthy, params \\ %{}) do
    {:ok, metadata} = Firmwares.metadata_from_firmware(firmware)
    firmware_metadata = if version, do: %{metadata | version: version}

    for _ <- 1..count do
      device = Fixtures.device_fixture(org, product, firmware, Map.put(params, :firmware_metadata, firmware_metadata))

      {:ok, _} =
        Health.save_device_health(%{
          "device_id" => device.id,
          "data" => %{},
          "status" => health,
          "status_reasons" => %{}
        })

      device
    end
  end

  # As `devices_on/4`, but each was last seen a day ago, so the Stands out
  # card counts it.
  defp seen_on(ctx, version, count, health \\ :healthy) do
    for device <- devices_on(ctx, version, count, health, %{status: :provisioned}) do
      Fixtures.device_connection_fixture(device, %{
        status: :disconnected,
        last_seen_at: DateTime.add(DateTime.utc_now(), -1, :day)
      })

      device
    end
  end

  describe "the composition bars" do
    test "count devices by connection, health and firmware, linking to each", %{conn: conn} = ctx do
      [online] = devices_on(ctx, "1.0.0", 1)
      Fixtures.device_connection_fixture(online, %{status: :connected})
      devices_on(ctx, "2.0.0", 3, :warning)

      conn
      |> visit(insights_path(ctx.org, ctx.product))
      |> within("#composition-connection", fn session ->
        session
        |> assert_has("a[href='#{devices_path(ctx.org, ctx.product, connection: "connected")}']", text: "Online 1")
        |> assert_has(
          "a[href='#{devices_path(ctx.org, ctx.product, advanced_query: ~s(connection = "not_seen"))}']",
          text: "Never connected 3"
        )
        |> assert_has("div", text: "25.0% online")
      end)
      |> within("#composition-health", fn session ->
        session
        |> assert_has("a[href='#{devices_path(ctx.org, ctx.product, health_status: "warning")}']", text: "Warning 3")
        |> refute_has("a", text: "Unhealthy")
      end)
      |> within("#composition-firmware", fn session ->
        session
        |> assert_has("a[href='#{devices_path(ctx.org, ctx.product, firmware_version: "2.0.0")}']", text: "2.0.0 3")
        |> assert_has("div", text: "75.0% on latest")
      end)
    end

    test "show shares of the fleet instead of counts", %{conn: conn} = ctx do
      devices_on(ctx, "1.0.0", 3)
      devices_on(ctx, "2.0.0", 1)

      conn
      |> visit(insights_path(ctx.org, ctx.product))
      # labelled "%" on a phone and "Percent" wider, so found by its value
      |> unwrap(&render_click(element(&1, "#composition-unit button[phx-value-unit=percent]")))
      |> within("#composition-firmware", fn session ->
        session
        |> assert_has("a", text: "1.0.0 75.0%")
        |> assert_has("a", text: "2.0.0 25.0%")
      end)
    end

    test "fold the smaller versions together past the fourth", %{conn: conn} = ctx do
      for {version, count} <- Enum.zip(1..7, 7..1//-1), do: devices_on(ctx, "#{version}.0.0", count)

      conn
      |> visit(insights_path(ctx.org, ctx.product))
      |> within("#composition-firmware", fn session ->
        session
        |> assert_has("a", text: "4.0.0")
        |> assert_has("span", text: "3 others 6")
        |> refute_has("a", text: "5.0.0")
      end)
    end

    test "link the devices with no firmware version to the Unknown filter", %{conn: conn} = ctx do
      devices_on(ctx, "1.0.0", 2)
      devices_on(ctx, nil, 1)

      conn
      |> visit(insights_path(ctx.org, ctx.product))
      |> assert_has(
        "#composition-firmware a[href='#{devices_path(ctx.org, ctx.product, firmware_version: "Unknown")}']",
        text: "Unknown 1"
      )
    end
  end

  describe "the version table and stands-out card" do
    test "name a version whose devices are much less healthy than the fleet's", %{conn: conn} = ctx do
      seen_on(ctx, "2.0.0", 30)
      seen_on(ctx, "1.0.0", 4)
      seen_on(ctx, "1.0.0", 6, :unhealthy)

      conn
      |> visit(insights_path(ctx.org, ctx.product))
      |> assert_has("#version-health tr[data-flagged]", text: "1.0.0")
      |> refute_has("#version-health tr[data-flagged]", text: "2.0.0")
      |> assert_has("#version-health li[data-flagged]", text: "1.0.0")
      |> assert_has("#version-health tfoot", text: "Total 40")
      |> within("#stands-out", fn session ->
        session
        |> assert_has("p", text: "6 of 10 devices on 1.0.0 aren't healthy, against 1 in 7 across the fleet.")
        |> assert_has("p", text: "All 6 are unhealthy. Every device on 2.0.0 is healthy.")
        # every device was seen this week, so there is no one to leave out
        |> refute_has("p", text: "Counts the")
        |> assert_has(
          "a[href='#{devices_path(ctx.org, ctx.product, firmware_version: "1.0.0", advanced_query: @active_not_healthy)}']",
          text: "View 6 not healthy"
        )
      end)
    end

    test "link each cell to the devices it counts", %{conn: conn} = ctx do
      devices_on(ctx, "2.0.0", 3)
      devices_on(ctx, "1.0.0", 2, :unhealthy)
      devices_on(ctx, nil, 1, :warning)

      offline = ~s(connection != "connected")

      conn
      |> visit(insights_path(ctx.org, ctx.product))
      |> within("#version-health table", fn session ->
        session
        |> assert_has(
          "tbody a[href='#{devices_path(ctx.org, ctx.product, firmware_version: "1.0.0", health_status: "unhealthy")}']",
          text: "2"
        )
        |> assert_has(
          "tbody a[href='#{devices_path(ctx.org, ctx.product, firmware_version: "Unknown", health_status: "warning")}']",
          text: "1"
        )
        |> assert_has(
          "tbody a[href='#{devices_path(ctx.org, ctx.product, firmware_version: "2.0.0", advanced_query: offline)}']",
          text: "3"
        )
        # an empty cell has nothing to list
        |> refute_has(
          "a[href='#{devices_path(ctx.org, ctx.product, firmware_version: "2.0.0", health_status: "unhealthy")}']"
        )
        |> assert_has("tfoot a[href='#{devices_path(ctx.org, ctx.product, health_status: "healthy")}']", text: "3")
        |> assert_has("tfoot a[href='#{devices_path(ctx.org, ctx.product, advanced_query: offline)}']", text: "6")
      end)
    end

    test "leave the folded versions' cells unlinked", %{conn: conn} = ctx do
      for {version, count} <- Enum.zip(1..6, 6..1//-1), do: devices_on(ctx, "#{version}.0.0", count)

      conn
      |> visit(insights_path(ctx.org, ctx.product))
      |> assert_has("#version-health tbody tr:last-child", text: "2 others")
      |> refute_has("#version-health tbody tr:last-child td a")
    end

    test "say what each device that isn't healthy is", %{conn: conn} = ctx do
      seen_on(ctx, "2.0.0", 27)
      seen_on(ctx, "2.0.0", 3, :warning)
      seen_on(ctx, "1.0.0", 4)
      seen_on(ctx, "1.0.0", 3, :warning)
      seen_on(ctx, "1.0.0", 2, :unhealthy)
      seen_on(ctx, "1.0.0", 1, :unknown)

      conn
      |> visit(insights_path(ctx.org, ctx.product))
      |> within("#stands-out", fn session ->
        session
        |> assert_has("p", text: "6 of 10 devices on 1.0.0 aren't healthy, against 1 in 4 across the fleet.")
        |> assert_has("p",
          text: "2 are unhealthy, 3 have warnings and 1 isn't reporting health. On 2.0.0 it's 1 in 10."
        )
      end)
    end

    test "leave out devices that haven't been seen in the last 7 days", %{conn: conn} = ctx do
      seen_on(ctx, "2.0.0", 18)
      seen_on(ctx, "2.0.0", 2, :unhealthy)
      # gone for weeks or never connected, with no health to report
      devices_on(ctx, "1.0.0", 12, :unknown, %{status: :provisioned})
      devices_on(ctx, "1.0.0", 3, :unknown)

      conn
      |> visit(insights_path(ctx.org, ctx.product))
      |> refute_has("#version-health tr[data-flagged]")
      |> within("#stands-out", fn session ->
        session
        |> assert_has("p", text: "Nothing stands out.")
        |> assert_has("p", text: "Counts the 20 of 35 devices seen in the last 7 days.")
        |> assert_has("span[title='No device on it was seen in the last 7 days']", text: "None seen")
        |> assert_has("a[href='#{devices_path(ctx.org, ctx.product, advanced_query: @active_not_healthy)}']",
          text: "View 2 not healthy"
        )
      end)
    end

    test "say a version needs enough devices to stand out", %{conn: conn} = ctx do
      seen_on(ctx, "2.0.0", 40)
      seen_on(ctx, "2.0.0", 2, :warning)
      seen_on(ctx, "1.0.0", 2)
      seen_on(ctx, "1.0.0", 3, :warning)

      conn
      |> visit(insights_path(ctx.org, ctx.product))
      |> within("#stands-out", fn session ->
        session
        |> assert_has("p", text: "Nothing stands out.")
        |> assert_has("p",
          text: "No version of 10 or more devices has 3 or more not healthy at twice the fleet's 10.6%"
        )
      end)
    end

    test "say when nothing stands out", %{conn: conn} = ctx do
      seen_on(ctx, "2.0.0", 18)
      seen_on(ctx, "2.0.0", 2, :warning)
      seen_on(ctx, "1.0.0", 9)
      seen_on(ctx, "1.0.0", 1, :warning)

      conn
      |> visit(insights_path(ctx.org, ctx.product))
      |> refute_has("#version-health tr[data-flagged]")
      |> within("#stands-out", fn session ->
        session
        |> assert_has("p", text: "Nothing stands out.")
        |> assert_has("p",
          text:
            "Every version is within a point of the fleet's 10.0% not healthy, so the 3 devices that need a look aren't tied to one firmware."
        )
        |> assert_has("a[href='#{devices_path(ctx.org, ctx.product, advanced_query: @active_not_healthy)}']",
          text: "View 3 not healthy"
        )
      end)
    end

    test "say when every device is healthy", %{conn: conn} = ctx do
      seen_on(ctx, "2.0.0", 3)
      seen_on(ctx, "1.0.0", 2)

      offline_this_week = ~s(connection != "connected" and connection != "not_seen" and not last_seen < "7 days ago")

      conn
      |> visit(insights_path(ctx.org, ctx.product))
      |> within("#stands-out", fn session ->
        session
        |> assert_has("p", text: "All 5 devices are healthy.")
        |> assert_has("p", text: "The 5 offline were healthy when they last reported.")
        |> assert_has("a[href='#{devices_path(ctx.org, ctx.product, advanced_query: offline_this_week)}']",
          text: "View 5 offline"
        )
      end)
    end

    test "say when no device was seen in the last 7 days", %{conn: conn} = ctx do
      devices_on(ctx, "2.0.0", 3)
      devices_on(ctx, "1.0.0", 2, :unknown)

      conn
      |> visit(insights_path(ctx.org, ctx.product))
      |> within("#stands-out", fn session ->
        session
        |> assert_has("p", text: "No device seen in the last 7 days.")
        |> assert_has("p", text: "none of the 5 has been.")
        |> assert_has("a[href='#{devices_path(ctx.org, ctx.product, advanced_query: ~s(connection != "connected"))}']",
          text: "View 5 offline"
        )
      end)
    end

    test "have nothing to compare with one version, and leave out the total", %{conn: conn} = ctx do
      seen_on(ctx, "1.0.0", 2)
      seen_on(ctx, "1.0.0", 1, :warning)

      conn
      |> visit(insights_path(ctx.org, ctx.product))
      |> assert_has("#stands-out p", text: "Nothing to compare yet.")
      |> assert_has("#stands-out p", text: "Every device runs 1.0.0")
      |> refute_has("#version-health tfoot")
    end
  end
end
