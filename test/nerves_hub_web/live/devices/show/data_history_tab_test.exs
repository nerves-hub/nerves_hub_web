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
    |> assert_has("#data-history-tab span", text: "No messages have been recorded yet.")
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
    |> assert_has("#data-history-tab span", text: "Newest first · last 4 messages")
    |> assert_has(row(), count: 4)
    |> assert_has(row("span"), text: "fwup_progress")
    |> assert_has(row("span"), text: ~s({"value":42}))
    |> assert_has(row("span"), text: "reboot")
    |> assert_has(row("span"), text: "health:check")
    |> assert_has(row("span"), text: "From device")
    |> assert_has(row("span"), text: "To device")
    |> assert_has(row("span"), text: "Extensions")
  end

  test "a row's details lay its payload out and offer to copy it", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    :ok = DeviceMessages.record(device, :received, :device, "fwup_progress", %{"value" => 42})
    :ok = Buffer.flush(DeviceMessage)

    conn
    |> visit(history_path(org, product, device))
    |> assert_has(row("div.whitespace-pre"), text: ~s({ "value": 42 }))
    |> assert_has(row("button[data-copy-value='{\"value\":42}']"), text: "Copy")
  end

  test "a truncated payload says how much was kept", %{conn: conn, org: org, product: product, device: device} do
    :ok = DeviceMessages.record(device, :received, :device, "noisy", %{"blob" => String.duplicate("a", 20_000)})
    :ok = Buffer.flush(DeviceMessage)

    conn
    |> visit(history_path(org, product, device))
    |> assert_has(row("span"), text: "Truncated for storage · 19.5 KB were sent, the first 8 KB kept")
  end

  for {label, topic, event} <- [{"console", :console, "up"}, {"local shell", :extensions, "local_shell:shell_output"}] do
    test "#{label} contents are never shown, only their size", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      :ok =
        DeviceMessages.record_size_only(device, :received, unquote(topic), unquote(event), %{
          "data" => "export SECRET=hunter2"
        })

      :ok = Buffer.flush(DeviceMessage)

      conn
      |> visit(history_path(org, product, device))
      |> assert_has(row("span"), text: "21 bytes (contents not recorded)")
      |> refute_has("#device-messages", text: "hunter2")
      |> refute_has(row("button[data-copy-value]"))
    end
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
    |> assert_has(row("span"), text: "https://firmware.example.com/fw.fw?[redacted]")
    |> refute_has("#device-messages", text: "deadbeef")
  end

  test "filtering by direction narrows the list", %{conn: conn, org: org, product: product, device: device} do
    :ok = DeviceMessages.record(device, :received, :device, "status_update", %{})
    :ok = DeviceMessages.record(device, :sent, :device, "reboot", %{})
    :ok = Buffer.flush(DeviceMessage)

    conn
    |> visit(history_path(org, product, device))
    |> assert_has(row("span"), text: "status_update")
    |> assert_has(row("span"), text: "reboot")
    |> click_button("[role=group] button", "To device")
    |> assert_has("[role=group] button[aria-pressed=true]", text: "To device")
    |> assert_path(history_path(org, product, device), query_params: %{direction: "sent", topic: "all"})
    |> assert_has(row("span"), text: "reboot")
    |> refute_has(row("span"), text: "status_update")
  end

  test "filtering by channel narrows the list", %{conn: conn, org: org, product: product, device: device} do
    :ok = DeviceMessages.record(device, :received, :device, "status_update", %{})
    :ok = DeviceMessages.record(device, :sent, :extensions, "health:check", %{})
    :ok = Buffer.flush(DeviceMessage)

    conn
    |> visit(history_path(org, product, device))
    |> select("Channel", option: "Extensions")
    |> assert_has(row("span"), text: "health:check")
    |> refute_has(row("span"), text: "status_update")
  end

  test "a filter in the url is applied on load", %{conn: conn, org: org, product: product, device: device} do
    :ok = DeviceMessages.record(device, :received, :device, "status_update", %{})
    :ok = DeviceMessages.record(device, :sent, :extensions, "health:check", %{})
    :ok = Buffer.flush(DeviceMessage)

    conn
    |> visit(history_path(org, product, device) <> "?topic=extensions")
    |> assert_has(row("span"), text: "health:check")
    |> refute_has(row("span"), text: "status_update")
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
    |> assert_has(row("span"), text: "status_update")
  end

  test "older messages are shown a page at a time", %{conn: conn, org: org, product: product, device: device} do
    for n <- 1..105, do: :ok = DeviceMessages.record(device, :sent, :device, "reboot", %{"n" => n})
    :ok = Buffer.flush(DeviceMessage)

    conn
    |> visit(history_path(org, product, device))
    |> assert_has(row(), count: 100)
    |> assert_has("#show-more-messages", text: "Show older messages")
    |> refute_has(row("span"), text: ~s({"n":5}))
    |> unwrap(fn view -> render_hook(view, "load-more-messages", %{}) end)
    |> assert_has(row(), count: 105)
    |> assert_has(row("span"), text: ~s({"n":1}))
    |> refute_has("#show-more-messages")
  end

  test "no older page is offered when everything is on screen", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    :ok = DeviceMessages.record(device, :sent, :device, "reboot", %{})
    :ok = Buffer.flush(DeviceMessage)

    conn
    |> visit(history_path(org, product, device))
    |> assert_has(row(), count: 1)
    |> refute_has("#show-more-messages")
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
      |> assert_has(row("span"), text: "status_update")
      |> refute_has(row("span"), text: "fwup_progress")

    :ok = DeviceMessages.record(device, :received, :device, "fwup_progress", %{"value" => 42})

    # Deliberately not flushed: a live message must appear without waiting for
    # its batch to reach ClickHouse.
    session
    |> assert_has(row("span"), text: "fwup_progress")
    |> assert_has("#data-history-tab span", text: "last 2 messages")
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
      |> assert_has(row("span"), text: "reboot")

    :ok = DeviceMessages.record(device, :received, :device, "status_update", %{})

    refute_has(session, row("span"), text: "status_update")
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
      |> assert_has(row("span"), text: "status_update")
      |> click_button("#toggle-message-streaming", "Pause")
      |> assert_has("#data-history-tab span", text: "Paused")

    :ok = DeviceMessages.record(device, :received, :device, "fwup_progress", %{"value" => 42})

    refute_has(session, row("span"), text: "fwup_progress")

    # Resuming refetches, so the message that arrived while paused is not lost.
    :ok = Buffer.flush(DeviceMessage)

    session
    |> click_button("#toggle-message-streaming", "Resume")
    |> assert_has(row("span"), text: "fwup_progress")
    |> assert_has("#data-history-tab span", text: "Live")
  end

  defp row(), do: "#device-messages [data-device-message]"
  defp row(selector), do: "#device-messages [data-device-message] #{selector}"

  defp history_path(org, product, device) do
    "/org/#{org.name}/#{product.name}/devices/#{device.identifier}/data_history"
  end
end
