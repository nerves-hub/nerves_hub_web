defmodule NervesHubWeb.API.DeviceLogControllerTest do
  # Not async: these tests read and write the AnalyticsRepo (ClickHouse), which
  # has no sandbox, and one of them toggles the global :analytics_enabled.
  use NervesHubWeb.APIConnCase, async: false

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices
  alias NervesHub.Devices.LogLine
  alias NervesHub.Devices.LogLines

  setup %{org: org, product: product} do
    {:ok, device} =
      Devices.create_device(%{
        identifier: "device-1234",
        description: "test device",
        tags: ["test"],
        org_id: org.id,
        product_id: product.id
      })

    :ok = Buffer.flush(LogLine)
    AnalyticsRepo.query!("TRUNCATE TABLE device_log_lines")

    on_exit(fn ->
      :ok = Buffer.flush(LogLine)
      AnalyticsRepo.query!("TRUNCATE TABLE device_log_lines")
    end)

    [device: device, now: DateTime.utc_now()]
  end

  defp path(conn, org, product, device, params \\ []) do
    Routes.api_device_log_path(conn, :index, org.name, product.name, device.identifier, params)
  end

  defp log(device, attrs) do
    device_info = %DeviceInfo{
      device_id: device.id,
      device_identifier: device.identifier,
      org_id: device.org_id,
      product_id: device.product_id
    }

    {:ok, log_line} =
      LogLines.async_create(device_info, %{
        "timestamp" => attrs[:timestamp] || DateTime.utc_now(),
        "level" => attrs[:level] || "info",
        "message" => attrs[:message] || "hello",
        "meta" => attrs[:meta] || %{}
      })

    :ok = Buffer.flush(LogLine)

    log_line
  end

  defp messages(response), do: Enum.map(response["data"], & &1["message"])

  describe "index" do
    test "is empty for a device that has logged nothing", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      conn = get(conn, path(conn, org, product, device))

      assert json_response(conn, 200)["data"] == []
    end

    test "returns a device's lines newest first", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      now: now
    } do
      log(device, message: "oldest", timestamp: DateTime.add(now, -60))
      log(device, message: "newest", timestamp: now)

      conn = get(conn, path(conn, org, product, device))

      assert messages(json_response(conn, 200)) == ["newest", "oldest"]
    end

    test "renders the whole line", %{conn: conn, org: org, product: product, device: device, now: now} do
      log(device, level: "error", message: "the sensor bus is gone", meta: %{"line" => "42"}, timestamp: now)

      conn = get(conn, path(conn, org, product, device))

      assert [line] = json_response(conn, 200)["data"]
      assert line["level"] == "error"
      assert line["message"] == "the sensor bus is gone"
      assert line["meta"] == %{"line" => "42"}
      assert {:ok, timestamp, _offset} = DateTime.from_iso8601(line["timestamp"])
      assert DateTime.compare(timestamp, now) == :eq
    end

    test "does not return another device's lines", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      {:ok, other} = Devices.create_device(%{identifier: "device-5678", org_id: org.id, product_id: product.id})

      log(other, message: "not yours")
      log(device, message: "yours")

      conn = get(conn, path(conn, org, product, device))

      assert messages(json_response(conn, 200)) == ["yours"]
    end

    test "keeps serving lines after the logging extension is turned off", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      log(device, message: "logged while it was on")

      {:ok, device} = Devices.update_device(device, %{extensions: %{logging: false}})

      conn = get(conn, path(conn, org, product, device))

      assert messages(json_response(conn, 200)) == ["logged while it was on"]
    end

    test "is reachable on the short device URL", %{conn: conn, device: device} do
      log(device, message: "hello")

      conn = get(conn, Routes.api_device_log_path(conn, :index, device.identifier))

      assert messages(json_response(conn, 200)) == ["hello"]
    end

    test "is refused for a user outside the organization", %{conn2: conn2, org: org, product: product, device: device} do
      assert_error_sent(404, fn -> get(conn2, path(conn2, org, product, device)) end)
      |> assert_authorization_error(404)
    end
  end

  describe "index, ordered" do
    test "oldest first with order=asc", %{conn: conn, org: org, product: product, device: device, now: now} do
      log(device, message: "oldest", timestamp: DateTime.add(now, -60))
      log(device, message: "newest", timestamp: now)

      conn = get(conn, path(conn, org, product, device, order: "asc"))

      assert messages(json_response(conn, 200)) == ["oldest", "newest"]
    end

    test "refuses an order it does not know", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, order: "sideways"))

      assert json_response(conn, 422)["errors"]["detail"] =~ "order must be asc or desc"
    end
  end

  describe "index, filtered by level" do
    setup %{device: device, now: now} do
      log(device, level: "debug", message: "debug line", timestamp: DateTime.add(now, -30))
      log(device, level: "info", message: "info line", timestamp: DateTime.add(now, -20))
      log(device, level: "error", message: "error line", timestamp: DateTime.add(now, -10))

      :ok
    end

    test "one level", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, level: "error"))

      assert messages(json_response(conn, 200)) == ["error line"]
    end

    test "several levels, comma separated", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, level: "error,debug"))

      assert messages(json_response(conn, 200)) == ["error line", "debug line"]
    end

    test "a level nothing has logged at matches nothing", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, level: "emergency"))

      assert json_response(conn, 200)["data"] == []
    end

    test "an empty level is no filter at all", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, level: ""))

      assert length(json_response(conn, 200)["data"]) == 3
    end
  end

  describe "index, searched" do
    setup %{device: device, now: now} do
      log(device, level: "error", message: "Failed to reach the sensor bus", timestamp: DateTime.add(now, -30))
      log(device, level: "info", message: "SENSOR BUS back online", timestamp: DateTime.add(now, -20))
      log(device, level: "info", message: "battery at 100% charge", timestamp: DateTime.add(now, -10))

      :ok
    end

    test "matches the message, ignoring case", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, search: "sensor bus"))

      assert messages(json_response(conn, 200)) == ["SENSOR BUS back online", "Failed to reach the sensor bus"]
    end

    test "matches a term nothing logged against nothing", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, search: "thermostat"))

      assert json_response(conn, 200)["data"] == []
    end

    test "takes wildcards literally", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, search: "%"))

      assert messages(json_response(conn, 200)) == ["battery at 100% charge"]
    end

    test "narrows alongside the other filters", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, search: "sensor bus", level: "error"))

      assert messages(json_response(conn, 200)) == ["Failed to reach the sensor bus"]
    end

    test "an empty search is no filter at all", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, search: "  "))

      assert length(json_response(conn, 200)["data"]) == 3
    end
  end

  describe "index, filtered by time" do
    setup %{device: device, now: now} do
      log(device, message: "old", timestamp: DateTime.add(now, -3600))
      log(device, message: "recent", timestamp: DateTime.add(now, -60))

      :ok
    end

    test "since is inclusive of its own second", %{conn: conn, org: org, product: product, device: device, now: now} do
      since = now |> DateTime.add(-60) |> DateTime.to_iso8601()

      conn = get(conn, path(conn, org, product, device, since: since))

      assert messages(json_response(conn, 200)) == ["recent"]
    end

    test "before excludes the line it names, so it can page", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      now: now
    } do
      before = now |> DateTime.add(-60) |> DateTime.to_iso8601()

      conn = get(conn, path(conn, org, product, device, before: before))

      assert messages(json_response(conn, 200)) == ["old"]
    end

    test "since and before together bound a window", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      now: now
    } do
      params = [
        since: now |> DateTime.add(-7200) |> DateTime.to_iso8601(),
        before: now |> DateTime.add(-600) |> DateTime.to_iso8601()
      ]

      conn = get(conn, path(conn, org, product, device, params))

      assert messages(json_response(conn, 200)) == ["old"]
    end

    test "refuses a timestamp it cannot read", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, since: "yesterday"))

      assert json_response(conn, 422)["errors"]["detail"] =~ "since must be an ISO 8601 timestamp"
    end
  end

  describe "index, limited" do
    test "returns at most the limit given", %{conn: conn, org: org, product: product, device: device, now: now} do
      for n <- 1..5, do: log(device, message: "line #{n}", timestamp: DateTime.add(now, -n))

      conn = get(conn, path(conn, org, product, device, limit: "2"))

      assert length(json_response(conn, 200)["data"]) == 2
    end

    test "refuses a limit that is not a number", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, limit: "lots"))

      assert json_response(conn, 422)["errors"]["detail"] =~ "limit must be a whole number between 1 and 1000"
    end

    test "refuses a limit above the maximum", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, limit: "1001"))

      assert json_response(conn, 422)["errors"]["detail"] =~ "limit must be a whole number between 1 and 1000"
    end

    test "refuses a limit below one", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, limit: "0"))

      assert json_response(conn, 422)["errors"]["detail"] =~ "limit must be a whole number between 1 and 1000"
    end
  end

  describe "index, without an analytics database" do
    setup do
      original = Application.get_env(:nerves_hub, :analytics_enabled)
      Application.put_env(:nerves_hub, :analytics_enabled, false)

      on_exit(fn -> Application.put_env(:nerves_hub, :analytics_enabled, original) end)
    end

    test "says so instead of answering with an empty list", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      conn = get(conn, path(conn, org, product, device))

      assert json_response(conn, 501)["errors"]["detail"] =~ "no analytics database configured"
    end
  end
end
