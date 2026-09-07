defmodule NervesHubWeb.Live.Devices.Show.DataHistoryTabTest do
  # Not async: these tests write to the AnalyticsRepo, which is a ClickHouse
  # database that does not support concurrent writes.
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices.DeviceMessage
  alias NervesHub.Devices.DeviceMessages

  setup context do
    original = Application.get_env(:nerves_hub, :analytics_enabled)
    on_exit(fn -> Application.put_env(:nerves_hub, :analytics_enabled, original) end)

    :ok = Buffer.flush(DeviceMessage)
    AnalyticsRepo.query("TRUNCATE TABLE device_messages", [])

    context
  end

  test "clickhouse (analytics) isn't enabled", %{conn: conn, org: org, product: product, device: device} do
    Application.put_env(:nerves_hub, :analytics_enabled, false)

    conn
    |> visit(history_path(org, product, device))
    |> assert_has("div", text: "Analytics aren't enabled for your platform.")
  end

  test "no messages have been recorded for the device", %{conn: conn, org: org, product: product, device: device} do
    conn
    |> visit(history_path(org, product, device))
    |> assert_has("div", text: "No messages have been recorded yet.")
  end

  test "shows messages in both directions across channels", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    :ok = DeviceMessages.record(device, :received, :device, "fwup_progress", %{"value" => 42})
    :ok = DeviceMessages.record(device, :sent, :device, "reboot", %{})
    :ok = DeviceMessages.record(device, :sent, :extensions, "health:check", %{})
    :ok = DeviceMessages.record_size_only(device, :received, :console, "up", %{"data" => "hello"})
    :ok = Buffer.flush(DeviceMessage)

    conn
    |> visit(history_path(org, product, device))
    |> assert_has("span", text: "Streaming the last 100 messages.")
    |> assert_has("td", text: "fwup_progress")
    |> assert_has("td", text: ~s({"value":42}))
    |> assert_has("td", text: "reboot")
    |> assert_has("td", text: "health:check")
    |> assert_has("span", text: "received")
    |> assert_has("span", text: "sent")
  end

  test "console contents are never shown, only their size", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    :ok =
      DeviceMessages.record_size_only(device, :received, :console, "up", %{
        "data" => "export SECRET=hunter2"
      })

    :ok = Buffer.flush(DeviceMessage)

    conn
    |> visit(history_path(org, product, device))
    |> assert_has("td", text: "21 bytes (contents not recorded)")
    |> refute_has("td", text: "hunter2")
  end

  test "a firmware url is shown without its signature", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    :ok =
      DeviceMessages.record(device, :sent, :device, "update", %{
        "url" => "https://firmware.example.com/fw.fw?X-Amz-Signature=deadbeef"
      })

    :ok = Buffer.flush(DeviceMessage)

    conn
    |> visit(history_path(org, product, device))
    |> assert_has("td", text: "https://firmware.example.com/fw.fw?[redacted]")
    |> refute_has("td", text: "deadbeef")
  end

  test "filtering by direction narrows the list", %{conn: conn, org: org, product: product, device: device} do
    :ok = DeviceMessages.record(device, :received, :device, "status_update", %{})
    :ok = DeviceMessages.record(device, :sent, :device, "reboot", %{})
    :ok = Buffer.flush(DeviceMessage)

    conn
    |> visit(history_path(org, product, device))
    |> assert_has("td", text: "status_update")
    |> assert_has("td", text: "reboot")
    |> select("Direction :", option: "Sent to device")
    |> assert_has("td", text: "reboot")
    |> refute_has("td", text: "status_update")
  end

  test "a filter in the url is applied on load", %{conn: conn, org: org, product: product, device: device} do
    :ok = DeviceMessages.record(device, :received, :device, "status_update", %{})
    :ok = DeviceMessages.record(device, :sent, :extensions, "health:check", %{})
    :ok = Buffer.flush(DeviceMessage)

    conn
    |> visit(history_path(org, product, device) <> "?topic=extensions")
    |> assert_has("td", text: "health:check")
    |> refute_has("td", text: "status_update")
  end

  test "an unrecognised filter shows everything rather than nothing", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    :ok = DeviceMessages.record(device, :received, :device, "status_update", %{})
    :ok = Buffer.flush(DeviceMessage)

    conn
    |> visit(history_path(org, product, device) <> "?topic=nonsense")
    |> assert_has("td", text: "status_update")
  end

  test "a message recorded while the tab is open is streamed in", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    :ok = DeviceMessages.record(device, :received, :device, "status_update", %{})
    :ok = Buffer.flush(DeviceMessage)

    session =
      conn
      |> visit(history_path(org, product, device))
      |> assert_has("td", text: "status_update")
      |> refute_has("td", text: "fwup_progress")

    :ok = DeviceMessages.record(device, :received, :device, "fwup_progress", %{"value" => 42})

    # Deliberately not flushed: a live message must appear without waiting for
    # its batch to reach ClickHouse.
    assert_has(session, "td", text: "fwup_progress")
  end

  test "a streamed message that does not match the filter is skipped", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    :ok = DeviceMessages.record(device, :sent, :device, "reboot", %{})
    :ok = Buffer.flush(DeviceMessage)

    session =
      conn
      |> visit(history_path(org, product, device) <> "?direction=sent")
      |> assert_has("td", text: "reboot")

    :ok = DeviceMessages.record(device, :received, :device, "status_update", %{})

    refute_has(session, "td", text: "status_update")
  end

  test "pausing stops new messages appearing, resuming catches up", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    :ok = DeviceMessages.record(device, :received, :device, "status_update", %{})
    :ok = Buffer.flush(DeviceMessage)

    session =
      conn
      |> visit(history_path(org, product, device))
      |> assert_has("td", text: "status_update")
      |> click_button("#toggle-message-streaming", "")

    :ok = DeviceMessages.record(device, :received, :device, "fwup_progress", %{"value" => 42})

    refute_has(session, "td", text: "fwup_progress")

    # Resuming refetches, so the message that arrived while paused is not lost.
    :ok = Buffer.flush(DeviceMessage)

    session
    |> click_button("#toggle-message-streaming", "")
    |> assert_has("td", text: "fwup_progress")
  end

  defp history_path(org, product, device) do
    "/org/#{org.name}/#{product.name}/devices/#{device.identifier}/data_history"
  end
end
