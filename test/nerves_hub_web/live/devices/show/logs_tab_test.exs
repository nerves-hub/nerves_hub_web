defmodule NervesHubWeb.Live.Devices.Show.LogsTabTest do
  # Not async: these tests write to the AnalyticsRepo, which is a ClickHouse
  # database that does not support concurrent writes.
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.LogLine
  alias NervesHub.Devices.LogLines
  alias NervesHub.Products.Product
  alias NervesHub.Repo

  setup context do
    original = Application.get_env(:nerves_hub, :analytics_enabled)
    on_exit(fn -> Application.put_env(:nerves_hub, :analytics_enabled, original) end)

    :ok = Buffer.flush(LogLine)
    AnalyticsRepo.query("TRUNCATE TABLE device_log_lines", [])

    context
  end

  test "clickhouse (analytics) isn't enabled", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    Application.put_env(:nerves_hub, :analytics_enabled, false)

    conn
    |> visit(logs_path(org, product, device))
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
    |> visit(logs_path(org, product, device))
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
    |> visit(logs_path(org, product, device))
    |> assert_has("div", text: "Device logs aren't enabled.")
    |> assert_has("div", text: "Please check the device settings.")
  end

  test "no device logs have been created for the device", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    enable_logging(product)

    conn
    |> visit(logs_path(org, product, device))
    |> assert_has("div", text: "No logs have been received yet.")
    # With nothing received there is nothing to search or narrow yet.
    |> refute_has("#log-filters")
  end

  test "recent device logs are shown", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    enable_logging(product)

    for n <- 1..5 do
      log(device, message: "something wicked this way comes : #{n}")
    end

    :ok = Buffer.flush(LogLine)

    conn
    |> visit(logs_path(org, product, device))
    |> assert_has("#log_lines > div", count: 5)
    |> assert_has("div", text: "something wicked this way comes : 1")
    |> assert_has("div", text: "something wicked this way comes : 2")
    |> assert_has("div", text: "something wicked this way comes : 3")
    |> assert_has("div", text: "something wicked this way comes : 4")
    |> assert_has("div", text: "something wicked this way comes : 5")
    # Everything fits on the first page, so there is nothing to show more of.
    |> refute_has("#show-more-logs")
  end

  test "new log lines are prepended to the recent device logs list", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    enable_logging(product)

    log(device, message: "something wicked this way comes")

    :ok = Buffer.flush(LogLine)

    session =
      conn
      |> visit(logs_path(org, product, device))
      |> assert_has("#log_lines > div", count: 1)
      |> assert_has("div", text: "something wicked this way comes")

    log(device, message: "something wicked this way comes, again")

    session
    |> assert_has("div", text: "something wicked this way comes, again")
    |> assert_has("#log_lines > div", count: 2)
  end

  test "new log lines are not prepended to the recent device logs list if streaming is turned off", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    enable_logging(product)

    log(device, message: "something wicked this way comes")

    :ok = Buffer.flush(LogLine)

    session =
      conn
      |> visit(logs_path(org, product, device))
      |> assert_has("div", text: "something wicked this way comes")
      |> click_button("#toggle-log-streaming", "")

    log(device, message: "something wicked this way comes, again")

    refute_has(session, "div", text: "something wicked this way comes, again", timeout: 500)
  end

  describe "going back" do
    test "the first page is the newest lines, and showing more reaches the older ones", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      enable_logging(product)
      insert_lines(device, 120)

      session =
        conn
        |> visit(logs_path(org, product, device))
        |> assert_has("#log_lines > div", count: 50)
        |> assert_has("div", text: line(120))
        |> assert_has("div", text: line(71))
        |> refute_has("div", text: line(70))
        |> assert_has("#show-more-logs")

      session =
        session
        |> show_more()
        |> assert_has("#log_lines > div", count: 100)
        |> assert_has("div", text: line(21))
        |> refute_has("div", text: line(20))
        |> assert_has("#show-more-logs")

      # The last page is short, which is how the tab knows there is no more,
      # and the button goes rather than offering a page with nothing in it.
      session
      |> show_more()
      |> assert_has("#log_lines > div", count: 120)
      |> assert_has("div", text: line(1))
      |> refute_has("#show-more-logs")
    end

    test "a list that is exactly one page has no show more", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      enable_logging(product)
      insert_lines(device, 50)

      conn
      |> visit(logs_path(org, product, device))
      |> assert_has("#log_lines > div", count: 50)
      |> refute_has("#show-more-logs")
    end

    test "showing more keeps to the filters", %{conn: conn, org: org, product: product, device: device} do
      enable_logging(product)
      insert_lines(device, 120, fn n -> if rem(n, 2) == 0, do: "error", else: "info" end)

      conn
      |> visit(logs_path(org, product, device) <> "?level=error")
      |> assert_has("#log_lines > div", count: 50)
      |> assert_has("#show-more-logs")
      |> show_more()
      |> assert_has("#log_lines > div", count: 60)
      |> assert_has("[data-log-level=error]", count: 60)
      |> refute_has("[data-log-level=info]")
      |> refute_has("#show-more-logs")
    end

    test "showing more with nothing to show is harmless", %{conn: conn, org: org, product: product, device: device} do
      enable_logging(product)
      insert_lines(device, 5)

      conn
      |> visit(logs_path(org, product, device))
      |> show_more()
      |> assert_has("#log_lines > div", count: 5)
    end

    test "the list stops growing at its limit, and says so", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      enable_logging(product)
      insert_lines(device, 1_100)

      session =
        conn
        |> visit(logs_path(org, product, device))
        |> assert_has("#show-more-logs")

      session = Enum.reduce(1..19, session, fn _page, session -> show_more(session) end)

      session
      |> assert_has("#log_lines > div", count: 1_000)
      |> assert_has("#log-limit-reached", text: "Showing the newest 1000 lines.")
      |> refute_has("#show-more-logs")
      # Asking again, as a stale page might, adds nothing.
      |> show_more()
      |> assert_has("#log_lines > div", count: 1_000)
      |> refute_has("div", text: line(100))
    end

    test "a full list drops its oldest line for each new one", %{conn: conn, org: org, product: product, device: device} do
      enable_logging(product)
      insert_lines(device, 1_100)

      session =
        conn
        |> visit(logs_path(org, product, device))
        |> then(fn session -> Enum.reduce(1..19, session, fn _page, session -> show_more(session) end) end)
        |> assert_has("#log_lines > div", count: 1_000)
        |> assert_has("div", text: line(101))

      log(device, message: "just arrived")

      session
      |> assert_has("div", text: "just arrived")
      |> assert_has("#log_lines > div", count: 1_000)
      |> refute_has("div", text: line(101))
      # The line that was pushed out is behind the limit, not something a later
      # page could have skipped, so the tab still says there is more.
      |> assert_has("#log-limit-reached")
    end
  end

  describe "search" do
    test "narrows the list to lines containing the text, ignoring case", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      enable_logging(product)
      log(device, message: "Sensor bus gone")
      log(device, message: "SENSOR BUS back")
      log(device, message: "polling temperature")
      :ok = Buffer.flush(LogLine)

      conn
      |> visit(logs_path(org, product, device))
      |> assert_has("div", text: "polling temperature")
      |> fill_in("Search log messages", with: "sensor bus")
      |> assert_has("div", text: "Sensor bus gone")
      |> assert_has("div", text: "SENSOR BUS back")
      |> refute_has("div", text: "polling temperature")
      |> assert_path(logs_path(org, product, device), query_params: %{"search" => "sensor bus"})
    end

    test "treats what is typed literally", %{conn: conn, org: org, product: product, device: device} do
      enable_logging(product)
      log(device, message: "battery at 100% charge")
      log(device, message: "polling temperature")
      :ok = Buffer.flush(LogLine)

      conn
      |> visit(logs_path(org, product, device))
      |> fill_in("Search log messages", with: "%")
      |> assert_has("div", text: "battery at 100% charge")
      |> refute_has("div", text: "polling temperature")
    end

    test "is applied from the url", %{conn: conn, org: org, product: product, device: device} do
      enable_logging(product)
      log(device, message: "Sensor bus gone")
      log(device, message: "polling temperature")
      :ok = Buffer.flush(LogLine)

      conn
      |> visit(logs_path(org, product, device) <> "?search=sensor")
      |> assert_has("div", text: "Sensor bus gone")
      |> refute_has("div", text: "polling temperature")
      |> assert_has("#log-search[value=sensor]")
    end

    test "says so when nothing matches, and clearing the filters brings everything back", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      enable_logging(product)
      log(device, message: "polling temperature")
      :ok = Buffer.flush(LogLine)

      conn
      |> visit(logs_path(org, product, device) <> "?search=nothing+logged+this")
      |> assert_has("div", text: "No log lines match these filters.")
      # The controls stay, so the search can be changed rather than only abandoned.
      |> assert_has("#log-filters")
      |> click_link("Clear filters")
      |> assert_has("div", text: "polling temperature")
      |> refute_has("div", text: "No log lines match these filters.")
      |> assert_path(logs_path(org, product, device))
    end
  end

  describe "level" do
    test "is a threshold: the chosen level and everything more severe", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      enable_logging(product)

      for level <- ~w(debug info notice warning warn error critical alert emergency) do
        log(device, level: level, message: "a #{level} line")
      end

      :ok = Buffer.flush(LogLine)

      session =
        conn
        |> visit(logs_path(org, product, device))
        |> assert_has("#log_lines > div", count: 9)
        |> select("Level :", option: "Warning and above")
        |> assert_has("#log_lines > div", count: 6)

      for level <- ~w(warning warn error critical alert emergency) do
        assert_has(session, "div", text: "a #{level} line")
      end

      for level <- ~w(debug info notice) do
        refute_has(session, "div", text: "a #{level} line")
      end

      session
      |> select("Level :", option: "Error and above")
      |> assert_has("#log_lines > div", count: 4)
      |> refute_has("div", text: "a warning line")
      |> select("Level :", option: "Info and above")
      |> assert_has("#log_lines > div", count: 8)
      |> refute_has("div", text: "a debug line")
      |> select("Level :", option: "All levels")
      |> assert_has("#log_lines > div", count: 9)
    end

    test "is applied from the url", %{conn: conn, org: org, product: product, device: device} do
      enable_logging(product)
      log(device, level: "info", message: "fine")
      log(device, level: "error", message: "broken")
      :ok = Buffer.flush(LogLine)

      conn
      |> visit(logs_path(org, product, device) <> "?level=error")
      |> assert_has("div", text: "broken")
      |> refute_has("div", text: "fine")
      |> assert_has("select[name=level] option[selected]", text: "Error and above")
    end
  end

  describe "time" do
    test "limits how far back to look", %{conn: conn, org: org, product: product, device: device} do
      enable_logging(product)
      now = DateTime.utc_now()

      log(device, message: "two hours ago", timestamp: DateTime.add(now, -2 * 3600))
      log(device, message: "half an hour ago", timestamp: DateTime.add(now, -30 * 60))
      log(device, message: "just now", timestamp: DateTime.add(now, -60))
      :ok = Buffer.flush(LogLine)

      conn
      |> visit(logs_path(org, product, device))
      |> assert_has("#log_lines > div", count: 3)
      |> select("Time :", option: "Last 6 hours")
      |> assert_has("#log_lines > div", count: 3)
      |> select("Time :", option: "Last hour")
      |> assert_has("div", text: "half an hour ago")
      |> assert_has("div", text: "just now")
      |> refute_has("div", text: "two hours ago")
      |> select("Time :", option: "Last 15 minutes")
      |> assert_has("div", text: "just now")
      |> refute_has("div", text: "half an hour ago")
      |> assert_path(logs_path(org, product, device), query_params: %{"range" => "15m"})
    end

    test "is applied from the url", %{conn: conn, org: org, product: product, device: device} do
      enable_logging(product)
      now = DateTime.utc_now()

      log(device, message: "two hours ago", timestamp: DateTime.add(now, -2 * 3600))
      log(device, message: "just now", timestamp: DateTime.add(now, -60))
      :ok = Buffer.flush(LogLine)

      conn
      |> visit(logs_path(org, product, device) <> "?range=1h")
      |> assert_has("div", text: "just now")
      |> refute_has("div", text: "two hours ago")
      |> assert_has("select[name=range] option[selected]", text: "Last hour")
    end
  end

  test "the filters combine", %{conn: conn, org: org, product: product, device: device} do
    enable_logging(product)
    log(device, level: "error", message: "sensor bus gone")
    log(device, level: "info", message: "sensor bus fine")
    log(device, level: "error", message: "wifi gone")
    :ok = Buffer.flush(LogLine)

    conn
    |> visit(logs_path(org, product, device) <> "?level=error&search=sensor")
    |> assert_has("#log_lines > div", count: 1)
    |> assert_has("div", text: "sensor bus gone")
  end

  test "an unrecognised filter shows everything rather than nothing", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    enable_logging(product)
    log(device, message: "polling temperature")
    :ok = Buffer.flush(LogLine)

    conn
    |> visit(logs_path(org, product, device) <> "?level=nonsense&range=forever")
    |> assert_has("div", text: "polling temperature")
  end

  describe "streaming with filters" do
    test "a new line that passes the filters is streamed in", %{conn: conn, org: org, product: product, device: device} do
      enable_logging(product)
      log(device, level: "error", message: "sensor bus gone")
      :ok = Buffer.flush(LogLine)

      session =
        conn
        |> visit(logs_path(org, product, device) <> "?level=error&search=sensor")
        |> assert_has("div", text: "sensor bus gone")

      log(device, level: "critical", message: "SENSOR BUS on fire")

      assert_has(session, "div", text: "SENSOR BUS on fire")
    end

    test "a new line that does not pass them is not", %{conn: conn, org: org, product: product, device: device} do
      enable_logging(product)
      log(device, level: "error", message: "sensor bus gone")
      :ok = Buffer.flush(LogLine)

      session =
        conn
        |> visit(logs_path(org, product, device) <> "?level=error&search=sensor")
        |> assert_has("div", text: "sensor bus gone")

      log(device, level: "info", message: "sensor bus fine")
      log(device, level: "error", message: "wifi gone")

      # Both would be in the list after a refresh only if they matched, and
      # neither does.
      refute_has(session, "div", text: "sensor bus fine", timeout: 500)
      refute_has(session, "div", text: "wifi gone", timeout: 500)
    end

    test "a line arriving when nothing matched yet replaces the empty message", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      enable_logging(product)
      log(device, message: "polling temperature")
      :ok = Buffer.flush(LogLine)

      session =
        conn
        |> visit(logs_path(org, product, device) <> "?search=sensor")
        |> assert_has("div", text: "No log lines match these filters.")

      log(device, message: "sensor bus gone")

      session
      |> assert_has("div", text: "sensor bus gone")
      |> refute_has("div", text: "No log lines match these filters.")
    end

    test "changing a filter while paused leaves streaming paused", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      enable_logging(product)
      log(device, level: "error", message: "sensor bus gone")
      :ok = Buffer.flush(LogLine)

      session =
        conn
        |> visit(logs_path(org, product, device))
        |> assert_has("div", text: "sensor bus gone")
        |> click_button("#toggle-log-streaming", "")
        |> select("Level :", option: "Error and above")
        |> assert_has("#toggle-log-streaming[aria-checked=false]")

      log(device, level: "error", message: "wifi gone")

      refute_has(session, "div", text: "wifi gone", timeout: 500)
    end

    test "resuming refetches with the filters that are set", %{conn: conn, org: org, product: product, device: device} do
      enable_logging(product)
      log(device, level: "error", message: "sensor bus gone")
      :ok = Buffer.flush(LogLine)

      session =
        conn
        |> visit(logs_path(org, product, device) <> "?level=error")
        |> assert_has("div", text: "sensor bus gone")
        |> click_button("#toggle-log-streaming", "")

      log(device, level: "error", message: "wifi gone")
      log(device, level: "info", message: "polling temperature")
      :ok = Buffer.flush(LogLine)

      session
      |> click_button("#toggle-log-streaming", "")
      |> assert_has("div", text: "wifi gone")
      |> refute_has("div", text: "polling temperature")
    end
  end

  defp logs_path(org, product, device) do
    "/org/#{org.name}/#{product.name}/devices/#{device.identifier}/logs"
  end

  defp enable_logging(product) do
    Product.changeset(product, %{"extensions" => %{"logging" => true}})
    |> Repo.update()
  end

  defp device_info(device) do
    %DeviceInfo{device_id: device.id, device_identifier: device.identifier, product_id: device.product_id}
  end

  # Goes through `async_create/2`, so the line is also announced to anyone
  # watching the device, which is what a connected tab is.
  defp log(device, attrs) do
    {:ok, log_line} =
      LogLines.async_create(device_info(device), %{
        "level" => attrs[:level] || "info",
        "timestamp" => attrs[:timestamp] || DateTime.utc_now(),
        "message" => attrs[:message] || "hello"
      })

    log_line
  end

  # Straight into ClickHouse, so a page's worth of lines can exist before the
  # tab is opened without being announced to it. Line `n` is logged `n` seconds
  # after the first, so the higher the number the newer the line.
  defp insert_lines(device, count, level_fun \\ fn _n -> "info" end) do
    base = DateTime.add(DateTime.utc_now(), -(count + 60), :second)

    rows =
      for n <- 1..count do
        LogLine.create_changeset(device.id, device.product_id, %{
          "timestamp" => DateTime.add(base, n, :second),
          "level" => level_fun.(n),
          "message" => line(n)
        }).changes
      end

    AnalyticsRepo.insert_all(LogLine, rows, settings: [async_insert: 1])

    :ok = Buffer.flush(LogLine)
  end

  # Padded so that no line's text is inside another's, which would let an
  # assertion about one be satisfied by its neighbour.
  defp line(n), do: "line-" <> String.pad_leading(Integer.to_string(n), 4, "0")

  # What the page's script does when "Show more" scrolls into view or is clicked.
  defp show_more(session) do
    unwrap(session, fn view -> render_hook(view, "load-more-logs", %{}) end)
  end
end
