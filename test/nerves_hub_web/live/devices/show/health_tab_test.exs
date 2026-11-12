defmodule NervesHubWeb.Live.Devices.Show.HealthTabTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  import Phoenix.HTML

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Scope
  alias NervesHub.Analytics.Buffer
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Alarms
  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.Devices.Health
  alias NervesHub.Devices.Metrics
  alias NervesHub.Products
  alias NervesHubWeb.Endpoint
  alias Phoenix.Socket.Broadcast

  @metrics %{
    "cpu_temp" => 41.381,
    "load_15min" => 0.06,
    "load_1min" => 0.55,
    "load_5min" => 0.15,
    "mem_size_mb" => 7892,
    "mem_used_mb" => 172,
    "mem_used_percent" => 2
  }

  # The charts drawn for `@metrics`: the 1 and 5 minute load averages give way
  # to the 15 minute one, and memory in megabytes to memory as a share.
  @charted_keys ["cpu_temp", "load_15min", "mem_used_percent"]

  setup %{device: device} = context do
    Endpoint.subscribe("device:#{device.id}")
    context
  end

  test "tab shows message when no health exist for device", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
    |> assert_has("#health-now", text: "No health metrics have been received from the device")
    |> refute_has("#health-history")
  end

  test "graph sections are displayed when metrics data exists", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    assert {:ok, 7} = save_metrics_with_timestamp(device, DateTime.now!("Etc/UTC"))

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
    |> assert_has("canvas", count: length(@charted_keys), timeout: 100)
    # Charts should be displayed for all time frames
    |> click_button("1 day")
    |> assert_has("canvas", count: length(@charted_keys), timeout: 100)
    |> click_button("7 days")
    |> assert_has("canvas", count: length(@charted_keys), timeout: 100)
    |> tap(fn session ->
      for metric <- @charted_keys, do: assert_has(session, "##{metric}-chart")
      for metric <- ["load_1min", "load_5min", "mem_used_mb"], do: refute_has(session, "##{metric}-chart")
    end)
  end

  describe "time frame selectors" do
    test "within 1 day", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      timestamp =
        DateTime.now!("Etc/UTC")
        |> DateTime.add(-4, :hour)
        |> DateTime.truncate(:millisecond)

      _ = save_metrics_with_timestamp(device, timestamp)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
      # Default time frame is 1 hour, so no charts are expected.
      |> assert_has("span", text: "No metrics for cpu_temp found for the selected period.", timeout: 100)
      |> then(fn socket ->
        @charted_keys
        |> Enum.reject(&(&1 == "cpu_temp"))
        |> Enum.reduce(socket, fn key, socket ->
          assert_has(socket, "span", text: "No metrics for #{key} found for the selected period.")
        end)
      end)
      |> click_button("1 day")
      |> refute_has("span", text: "No metrics for cpu_temp found for the selected period.", timeout: 100)
      |> then(fn socket ->
        @charted_keys
        |> Enum.reject(&(&1 == "cpu_temp"))
        |> Enum.reduce(socket, fn key, socket ->
          refute_has(socket, "span", text: "No metrics for #{key} found for the selected period.")
        end)
      end)
      |> click_button("7 days")
      |> refute_has("span", text: "No metrics for cpu_temp found for the selected period.", timeout: 100)
      |> then(fn socket ->
        @charted_keys
        |> Enum.reject(&(&1 == "cpu_temp"))
        |> Enum.reduce(socket, fn key, socket ->
          refute_has(socket, "span", text: "No metrics for #{key} found for the selected period.")
        end)
      end)
      # Makes sure "3 hours" button is working
      |> click_button("3 hours")
      |> assert_has("span", text: "No metrics for cpu_temp found for the selected period.", timeout: 100)
      |> then(fn socket ->
        @charted_keys
        |> Enum.reject(&(&1 == "cpu_temp"))
        |> Enum.reduce(socket, fn key, socket ->
          assert_has(socket, "span", text: "No metrics for #{key} found for the selected period.")
        end)
      end)
    end

    test "within 7 days", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      timestamp =
        DateTime.now!("Etc/UTC")
        # Just outside span for 7 days
        |> DateTime.add(-7, :day)
        |> DateTime.truncate(:millisecond)

      _ = save_metrics_with_timestamp(device, timestamp)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
      |> assert_has("span", text: "No metrics for cpu_temp found for the selected period.", timeout: 100)
      |> then(fn socket ->
        @charted_keys
        |> Enum.reject(&(&1 == "cpu_temp"))
        |> Enum.reduce(socket, fn key, socket ->
          assert_has(socket, "span", text: "No metrics for #{key} found for the selected period.")
        end)
      end)
      |> click_button("1 day")
      |> assert_has("span", text: "No metrics for cpu_temp found for the selected period.", timeout: 100)
      |> then(fn socket ->
        @charted_keys
        |> Enum.reject(&(&1 == "cpu_temp"))
        |> Enum.reduce(socket, fn key, socket ->
          assert_has(socket, "span", text: "No metrics for #{key} found for the selected period.")
        end)
      end)
      |> click_button("7 days")
      |> assert_has("span", text: "No metrics for cpu_temp found for the selected period.", timeout: 100)
      |> then(fn socket ->
        @charted_keys
        |> Enum.reject(&(&1 == "cpu_temp"))
        |> Enum.reduce(socket, fn key, socket ->
          assert_has(socket, "span", text: "No metrics for #{key} found for the selected period.")
        end)
      end)

      timestamp =
        DateTime.now!("Etc/UTC")
        # Outside span for 1 day, but within 7 days
        |> DateTime.add(-1, :day)
        |> DateTime.truncate(:millisecond)

      _ = save_metrics_with_timestamp(device, timestamp)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
      |> assert_has("span", text: "No metrics for cpu_temp found for the selected period.", timeout: 100)
      |> then(fn socket ->
        @charted_keys
        |> Enum.reject(&(&1 == "cpu_temp"))
        |> Enum.reduce(socket, fn key, socket ->
          assert_has(socket, "span", text: "No metrics for #{key} found for the selected period.")
        end)
      end)
      |> click_button("1 day")
      |> assert_has("span", text: "No metrics for cpu_temp found for the selected period.", timeout: 100)
      |> then(fn socket ->
        @charted_keys
        |> Enum.reject(&(&1 == "cpu_temp"))
        |> Enum.reduce(socket, fn key, socket ->
          assert_has(socket, "span", text: "No metrics for #{key} found for the selected period.")
        end)
      end)
      |> click_button("7 days")
      |> refute_has("span", text: "No metrics for cpu_temp found for the selected period.", timeout: 100)
      |> then(fn socket ->
        @charted_keys
        |> Enum.reject(&(&1 == "cpu_temp"))
        |> Enum.reduce(socket, fn key, socket ->
          refute_has(socket, "span", text: "No metrics for #{key} found for the selected period.")
        end)
      end)
    end
  end

  test "charts are updating when metrics are reported", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
    |> assert_has("#health-now", text: "No health metrics have been received from the device")
    |> unwrap(fn view ->
      assert {:ok, 7} = save_metrics_with_timestamp(device, DateTime.now!("Etc/UTC"))

      send(view.pid, %Broadcast{
        topic: "internal:device:#{device.id}",
        event: "health_check_report",
        payload: %{}
      })

      render(view)
    end)
    |> then(fn socket ->
      Enum.reduce(@charted_keys, socket, fn key, socket ->
        socket
        |> assert_has("##{key}-chart", timeout: 100)
        |> refute_has("span", text: "No metrics for #{key} found for the selected period.")
      end)
    end)
  end

  test "memory used is shown without a percentage", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    assert {:ok, 1} = record_metrics(device, %{"mem_used_mb" => 100}, DateTime.now!("Etc/UTC"))

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
    |> assert_has("#health-tile-memory", text: "100")
    |> assert_has("#health-tile-memory", text: "MB")
    |> refute_has("#health-tile-memory", text: "%")
    |> assert_has("#mem_used_mb-chart", timeout: 100)
  end

  test "metrics data is correctly structured for js graphs", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    now = DateTime.now!("Etc/UTC")
    value = 0.55

    assert {:ok, 1} = record_metrics(device, %{"load_1min" => value}, now)

    {:ok, lv, _html} =
      live(conn, "/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")

    organized_metrics =
      ~s([{"x":#{DateTime.to_unix(now, :millisecond)},"y":#{value}}])
      |> html_escape()
      |> safe_to_string()

    assert render_async(lv, 1000) =~ ~s(data-metrics="#{organized_metrics}")
  end

  describe "custom graph labels" do
    test "default labels are shown above charts with an edit affordance", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      _ = save_metrics_with_timestamp(device, DateTime.now!("Etc/UTC"))

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
      |> assert_has("#health-chart-load_15min h3", text: "Load average")
      |> assert_has("#health-chart-load_15min", text: "15 min")
      |> assert_has("button[phx-click=edit-health-label][phx-value-key=load_15min]")
    end

    test "a label can be edited and saved", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      _ = save_metrics_with_timestamp(device, DateTime.now!("Etc/UTC"))

      {:ok, view, _html} =
        live(conn, "/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")

      # entering edit mode shows the input
      html = render_click(view, "edit-health-label", %{"key" => "load_15min"})
      assert html =~ ~s(name="label")

      # saving persists the custom label and renders it
      html = render_submit(view, "save-health-label", %{"key" => "load_15min", "label" => "15 Minute Load"})

      assert html =~ "15 Minute Load"
      assert Products.custom_health_metrics_labels(product) == %{"load_15min" => "15 Minute Load"}
    end

    test "saving a blank label reverts to the default", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      {:ok, _} = Products.set_custom_health_metrics_label(product, "load_15min", "15 Minute Load")

      _ = save_metrics_with_timestamp(device, DateTime.now!("Etc/UTC"))

      {:ok, view, html} =
        live(conn, "/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")

      assert html =~ "15 Minute Load"

      html = render_submit(view, "save-health-label", %{"key" => "load_15min", "label" => ""})

      refute html =~ "15 Minute Load"
      assert html =~ "Load average"
      assert Products.custom_health_metrics_labels(product) == %{}
    end

    test "users without the manage role cannot edit labels", %{
      conn: conn,
      org: org,
      user: user,
      product: product,
      device: device
    } do
      scope = Scope.for_user(user) |> Scope.put_org(org)
      org_user = Accounts.get_org_user!(scope, user)
      Accounts.change_org_user_role(org_user, :view)

      _ = save_metrics_with_timestamp(device, DateTime.now!("Etc/UTC"))

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
      |> assert_has("#health-chart-load_15min h3", text: "Load average")
      |> refute_has("button[phx-click=edit-health-label]")
    end
  end

  describe "the Now card" do
    test "marks each reading against the thresholds of the device's profile", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      {:ok, _} =
        record_metrics(
          device,
          %{
            "cpu_usage_percent" => 3,
            "mem_used_percent" => 88,
            "mem_used_mb" => 1612,
            "mem_size_mb" => 1832,
            "disk_used_percentage" => 78,
            "disk_total_kb" => 31_457_280,
            "disk_available_kb" => 6_815_744,
            "cpu_temp" => 46,
            "load_1min" => 0.39,
            "load_5min" => 0.26,
            "load_15min" => 0.19
          },
          DateTime.now!("Etc/UTC")
        )

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
      |> assert_has("#health-now a", text: "Default profile")
      |> assert_has("#health-tile-cpu", text: "Warning 80% · Alert 90%")
      |> assert_has("#health-tile-memory", text: "1,612 of 1,832 MB")
      |> assert_has("#health-tile-memory", text: "Warning 70% · Alert 80%")
      |> assert_has("#health-tile-disk", text: "23.5 of 30 GB")
      |> assert_has("#health-tile-cpu-temperature", text: "No thresholds set")
      |> assert_has("#health-tile-load", text: "0.39")
      |> assert_has("#health-tile-load", text: "15 min: Warning 8 · Alert 10")
      # The charts judge the latest reading against the same thresholds.
      |> assert_has("#health-chart-mem_used_percent", text: "Above alert")
      |> assert_has("#health-chart-cpu_temp", text: "No thresholds set")
      |> assert_has("#health-chart-load_15min", text: "Thresholds 8 and 10 are above this scale")
    end

    test "says why a metric engaged its level", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      {:ok, _} = record_metrics(device, %{"mem_used_percent" => 88}, DateTime.now!("Etc/UTC"))

      {:ok, _} =
        Health.save_device_health(%{
          "device_id" => device.id,
          "data" => %{"metrics" => %{"mem_used_percent" => 88}},
          "status" => :warning,
          "status_reasons" => %{
            "warning" => %{
              "mem_used_percent" => %{
                "aggregation" => "share",
                "operator" => "gte",
                "threshold" => 70,
                "value" => 62,
                "period_seconds" => 3600
              }
            }
          }
        })

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
      |> assert_has("#health-tile-memory .text-warning-content", text: "≥ 70% for 62% of the last hour")
    end

    test "lists the device's active alarms", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      session =
        conn
        |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
        |> assert_has("#health-alarms", text: "None active")

      :ok = Alarms.raise_alarm(to_device_info(device), "DiskAlmostFull", "/data")

      session
      |> assert_has("#health-alarms", text: "1 active", timeout: 1000)
      |> assert_has("#health-alarms code", text: "DiskAlmostFull")
      |> assert_has("#health-alarms li", text: "since")
    end
  end

  test "rendering a device-reported metric key mints no atoms", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    # Metric keys are whatever the device put in its health report, and atoms
    # are never reclaimed -- so deriving assign keys from them used to make the
    # node permanently heavier for every novel key a fleet reported.
    key = "totally_novel_metric_#{System.unique_integer([:positive])}"

    {:ok, 1} = record_metrics(device, %{key => 12.5}, DateTime.now!("Etc/UTC"))

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
    |> assert_has("##{key}-chart", timeout: 100)

    # Asserted on the specific atoms rather than on `:erlang.system_info(:atom_count)`,
    # which is global and moves under any other test running alongside this one.
    # These two are what the tab used to derive from the metric name.
    for never_an_atom <- [key <> "_chart_data", key <> "_has_chart_data"] do
      assert_raise ArgumentError, fn -> String.to_existing_atom(never_an_atom) end
    end
  end

  describe "chart style" do
    test "draws lines until the user picks scatter, and remembers it", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user
    } do
      assert {:ok, 7} = save_metrics_with_timestamp(device, DateTime.now!("Etc/UTC"))

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
      |> assert_has("canvas[data-chart-style=line]", count: length(@charted_keys), timeout: 100)
      |> assert_has("[aria-label='Chart style'] button[aria-label=Line][aria-pressed=true]")
      |> click_button("Scatter")
      |> assert_has("[aria-label='Chart style'] button[aria-label=Scatter][aria-pressed=true]")

      assert Accounts.get_user!(user.id).display_preferences.health_chart_style == :scatter

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
      |> assert_has("canvas[data-chart-style=scatter]", count: length(@charted_keys), timeout: 100)
    end
  end

  describe "zoom" do
    test "names the zoomed span and offers to reset it", %{conn: conn, org: org, product: product, device: device} do
      assert {:ok, 7} = save_metrics_with_timestamp(device, DateTime.now!("Etc/UTC"))

      from = DateTime.add(DateTime.utc_now(), -90, :minute)
      until = DateTime.add(DateTime.utc_now(), -30, :minute)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
      |> assert_has("#health-history", text: "Drag across a chart to zoom")
      |> refute_has("button", text: "Reset zoom")
      |> unwrap(fn view ->
        render_hook(view, "charts-zoomed", %{
          "from" => DateTime.to_unix(from, :millisecond),
          "until" => DateTime.to_unix(until, :millisecond)
        })
      end)
      |> refute_has("#health-history", text: "Drag across a chart to zoom")
      |> click_button("Reset zoom")
      |> refute_has("button", text: "Reset zoom")
      |> assert_has("#health-history", text: "Drag across a chart to zoom")
    end
  end

  defp save_metrics_with_timestamp(device, timestamp), do: record_metrics(device, @metrics, timestamp)

  defp to_device_info(device) do
    %DeviceInfo{
      device_id: device.id,
      device_identifier: device.identifier,
      org_id: device.org_id,
      product_id: device.product_id
    }
  end

  defp record_metrics(device, metrics, timestamp) do
    result = Metrics.record(to_device_info(device), metrics, timestamp)

    # The charts read ClickHouse, and the write is buffered. Without this the
    # assertions race the flush.
    :ok = Buffer.flush(DeviceMetric)

    result
  end
end
