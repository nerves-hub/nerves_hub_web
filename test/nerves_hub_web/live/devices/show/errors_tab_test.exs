defmodule NervesHubWeb.Live.Devices.Show.ErrorsTabTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Device
  alias NervesHub.ErrorReports
  alias NervesHub.ErrorReports.ErrorReport
  alias NervesHub.ErrorReports.GroupBuffer
  alias NervesHub.Fixtures
  alias NervesHub.Products.Product
  alias NervesHub.Repo

  setup context do
    original = Application.get_env(:nerves_hub, :analytics_enabled)
    on_exit(fn -> Application.put_env(:nerves_hub, :analytics_enabled, original) end)

    :ok = Buffer.flush(ErrorReport)
    :ok = GroupBuffer.flush()
    AnalyticsRepo.query("TRUNCATE TABLE device_error_reports", [])

    context
  end

  defp enable(product) do
    {:ok, product} = Product.changeset(product, %{"extensions" => %{"error_reports" => true}}) |> Repo.update()
    product
  end

  defp errors_path(org, product, device), do: "/org/#{org.name}/#{product.name}/devices/#{device.identifier}/errors"

  defp report(reason, overrides \\ %{}) do
    Map.merge(
      %{
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "kind" => "error",
        "reason" => reason,
        "frames" => [%{"module" => "MyApp.Worker", "function" => "run/0", "file" => "w.ex", "line" => 3}]
      },
      overrides
    )
  end

  defp record(device, reports) do
    info = %DeviceInfo{
      org_id: device.org_id,
      product_id: device.product_id,
      device_id: device.id,
      device_identifier: device.identifier,
      firmware_metadata: %{uuid: "fw-1"}
    }

    {:ok, _stored} = ErrorReports.record_batch(info, reports)

    :ok = Buffer.flush(ErrorReport)
    :ok = GroupBuffer.flush()
  end

  describe "gating" do
    test "analytics aren't enabled for the platform", %{conn: conn, org: org, product: product, device: device} do
      Application.put_env(:nerves_hub, :analytics_enabled, false)

      conn
      |> visit(errors_path(org, product, device))
      |> assert_has("div", text: "Analytics aren't enabled for your platform.")
    end

    test "error reports aren't enabled for the product", %{conn: conn, org: org, product: product, device: device} do
      conn
      |> visit(errors_path(org, product, device))
      |> assert_has("div", text: "Error reports aren't enabled for this product.")
      |> assert_has("div", text: "Please check the product settings.")
    end

    test "error reports aren't enabled for the device", %{conn: conn, org: org, product: product, device: device} do
      product = enable(product)
      {:ok, _device} = Device.changeset(device, %{"extensions" => %{"error_reports" => false}}) |> Repo.update()

      conn
      |> visit(errors_path(org, product, device))
      |> assert_has("div", text: "Error reports aren't enabled for this device.")
      |> assert_has("div", text: "Please check the device settings.")
    end
  end

  describe "the list" do
    test "says so when nothing has been reported", %{conn: conn, org: org, product: product, device: device} do
      product = enable(product)

      conn
      |> visit(errors_path(org, product, device))
      |> assert_has("div", text: "No errors have been reported.")
    end

    test "shows reported errors, grouped", %{conn: conn, org: org, product: product, device: device} do
      product = enable(product)

      record(device, [
        report("** (RuntimeError) the sensor bus is unreachable"),
        report("** (RuntimeError) the sensor bus is unreachable"),
        report("** (MatchError) no match of right hand side value: {:error, :enoent}")
      ])

      conn
      |> visit(errors_path(org, product, device))
      |> assert_has("div", text: "** (RuntimeError) the sensor bus is unreachable")
      |> assert_has("div", text: "** (MatchError) no match of right hand side value: {:error, :enoent}")
      |> assert_has("td", text: "unresolved")
      # Two occurrences of one error is one row saying 2, not two rows.
      |> assert_has("td", text: "2")
    end

    test "shows the top frame under the reason", %{conn: conn, org: org, product: product, device: device} do
      product = enable(product)
      record(device, [report("boom")])

      conn
      |> visit(errors_path(org, product, device))
      |> assert_has("div", text: "MyApp.Worker.run/0")
    end

    test "counts only this device's occurrences", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      firmware: firmware
    } do
      product = enable(product)
      other = Fixtures.device_fixture(org, product, firmware, %{identifier: "other-device"})

      record(device, [report("shared failure")])
      record(other, [report("shared failure"), report("shared failure")])

      conn
      |> visit(errors_path(org, product, device))
      |> assert_has("td", text: "1")
    end
  end

  describe "expanding a row" do
    setup %{product: product, device: device} do
      product = enable(product)

      record(device, [
        report("** (RuntimeError) boom", %{
          "message" => "GenServer MyApp.Worker terminating",
          "context" => %{"queue" => "uploads", "uptime_ms" => "7200000", "reboot_count" => "2"}
        })
      ])

      %{product: product}
    end

    test "shows the latest occurrence's stacktrace and context", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      conn
      |> visit(errors_path(org, product, device))
      |> click_button("+")
      |> assert_has("div", text: "GenServer MyApp.Worker terminating")
      |> assert_has("span", text: "MyApp.Worker.run/0")
      |> assert_has("span", text: "queue:")
      # A recognised vital key gets a friendly label and unit; the raw
      # `uptime_ms: 7200000` never reaches the screen.
      |> assert_has("span", text: "uptime:")
      |> assert_has("span", text: "2h")
      |> assert_has("span", text: "reboots:")
    end

    test "links through to the fleet-wide view", %{conn: conn, org: org, product: product, device: device} do
      conn
      |> visit(errors_path(org, product, device))
      |> click_button("+")
      |> assert_has("a", text: "See this error across the fleet")
    end
  end

  describe "live updates" do
    test "an arriving error refreshes the list", %{conn: conn, org: org, product: product, device: device} do
      product = enable(product)

      session =
        conn
        |> visit(errors_path(org, product, device))
        |> assert_has("div", text: "No errors have been reported.")

      record(device, [report("** (RuntimeError) arrived while watching")])

      # The tab coalesces arrivals into one refresh rather than querying per
      # occurrence, so the list catches up a moment later.
      Process.sleep(to_timeout(second: 4))

      assert_has(session, "div", text: "** (RuntimeError) arrived while watching")
    end
  end
end
