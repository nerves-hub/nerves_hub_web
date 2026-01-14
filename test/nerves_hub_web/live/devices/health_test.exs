defmodule NervesHubWeb.Devices.HealthTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Phoenix.HTML

  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.Repo
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

  setup %{fixture: %{device: device}} do
    Endpoint.subscribe("device:#{device.id}")
  end

  test "assert page render when no health exist for device", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
    |> assert_has("div", text: "Health over time")
    |> assert_has("span", text: "No metrics for the selected period.")
  end

  test "Assert canvas is rendered when metrics data exists", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    assert {7, _} = save_metrics_with_timestamp(device.id, DateTime.now!("Etc/UTC"))

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
    # Six of the default metric types are shown as charts
    |> assert_has("canvas", count: 6)
    # Charts should be displayed for all time frames
    |> click_button("1 day")
    |> assert_has("canvas", count: 6)
    |> click_button("7 days")
    |> assert_has("canvas", count: 6)
    |> tap(fn session ->
      # Assert all default metrics except "size_mb" appears as element id:s
      for metric <- Map.keys(@metrics),
          metric != "mem_size_mb",
          do: assert_has(session, "##{metric}")
    end)
  end

  test "assert time frame shows correct metrics - within 1 day", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    timestamp =
      DateTime.now!("Etc/UTC")
      |> DateTime.add(-23, :hour)
      |> DateTime.truncate(:millisecond)

    _ = save_metrics_with_timestamp(device.id, timestamp)

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
    # Default time frame is 1 hour, so no charts are expected.
    |> refute_has("canvas")
    |> click_button("1 day")
    |> assert_has("canvas")
    |> click_button("7 days")
    |> assert_has("canvas")
    # Makes sure "1 hour" button is working
    |> click_button("1 hour")
    |> refute_has("canvas")
  end

  test "assert time frame shows correct metrics - within 7 days", %{
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

    _ = save_metrics_with_timestamp(device.id, timestamp)

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
    |> refute_has("canvas")
    |> click_button("1 day")
    |> refute_has("canvas")
    |> click_button("7 days")
    |> refute_has("canvas")

    timestamp =
      DateTime.now!("Etc/UTC")
      # Outside span for 1 day, but within 7 days
      |> DateTime.add(-1, :day)
      |> DateTime.truncate(:millisecond)

    _ = save_metrics_with_timestamp(device.id, timestamp)

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
    |> refute_has("canvas")
    |> click_button("1 day")
    |> refute_has("canvas")
    |> click_button("7 days")
    |> assert_has("canvas")
  end

  test "assert charts are updating when metrics are reported", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
    |> refute_has("canvas")
    |> unwrap(fn view ->
      assert {7, _} = save_metrics_with_timestamp(device.id, DateTime.now!("Etc/UTC"))

      send(view.pid, %Broadcast{
        topic: "device:#{device.identifier}:internal",
        event: "health_check_report",
        payload: %{}
      })

      render(view)
    end)
    |> assert_has("canvas")
  end

  test "assert metrics data is correctly structured for js graphs", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    now = DateTime.now!("Etc/UTC")
    value = 0.55

    assert {:ok, _} =
             %{
               device_id: device.id,
               key: "load_1min",
               value: value,
               inserted_at: now
             }
             |> DeviceMetric.save_with_timestamp()
             |> Repo.insert()

    {:ok, _view, html} =
      live(conn, "/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")

    organized_metrics =
      ~s([{"y":#{value},"x":"#{now}"}])
      |> html_escape()
      |> safe_to_string()

    assert html =~ ~s(data-metrics="#{organized_metrics}")
  end

  defp save_metrics_with_timestamp(device_id, timestamp) do
    entries =
      Enum.map(@metrics, fn {key, val} ->
        DeviceMetric.save_with_timestamp(%{
          device_id: device_id,
          key: key,
          value: val,
          inserted_at: timestamp
        }).changes
      end)

    Repo.insert_all(DeviceMetric, entries)
  end
end
