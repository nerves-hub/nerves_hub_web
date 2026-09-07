defmodule NervesHubWeb.Live.Product.InsightsFirmwareVersionsTest do
  # Not async: mounting the insights page reads the AnalyticsRepo (ClickHouse).
  use NervesHubWeb.ConnCase.Browser, async: false

  import Phoenix.LiveViewTest

  alias NervesHub.Firmwares
  alias NervesHub.Fixtures

  setup %{user: user, org: org, org_key: org_key, tmp_dir: tmp_dir} do
    product = Fixtures.product_fixture(user, org, %{name: "Firmware Versions"})
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

    %{product: product, firmware: firmware}
  end

  defp insights_path(org, product), do: ~p"/org/#{org}/#{product}/insights"

  defp device_on_version(org, product, firmware, version) do
    {:ok, metadata} = Firmwares.metadata_from_firmware(firmware)

    Fixtures.device_fixture(org, product, firmware, %{
      firmware_metadata: %{metadata | version: version}
    })
  end

  describe "the firmware versions donut" do
    test "renders a slice per version, largest first, with counts and shares", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      for _ <- 1..3, do: device_on_version(org, product, firmware, "1.0.0")
      device_on_version(org, product, firmware, "0.9.0")

      {:ok, view, html} = live(conn, insights_path(org, product))

      assert html =~ "Firmware Versions"
      assert html =~ ~s(phx-hook="DonutChart")

      assigns = :sys.get_state(view.pid).socket.assigns

      assert assigns.firmware_version_slices == [
               %{label: "1.0.0", filter: "1.0.0", count: 3},
               %{label: "0.9.0", filter: "0.9.0", count: 1}
             ]

      assert assigns.firmware_version_count == 2
      assert assigns.firmware_version_total == 4
      refute assigns.firmware_version_other

      # the legend carries the counts and shares, so identity is never colour alone
      assert has_element?(view, "#firmware-versions-chart")
      assert render(view) =~ "75%"
      assert render(view) =~ "25%"
    end

    test "groups devices that haven't reported firmware under Unknown", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      device_on_version(org, product, firmware, "1.0.0")
      Fixtures.device_fixture(org, product, firmware, %{firmware_metadata: nil})

      {:ok, view, _html} = live(conn, insights_path(org, product))

      assigns = :sys.get_state(view.pid).socket.assigns

      assert %{label: "Unknown", filter: "Unknown", count: 1} in assigns.firmware_version_slices
      # "Unknown" isn't a version, so it doesn't count towards the version total
      assert assigns.firmware_version_count == 1
    end

    test "folds everything past the sixth version into an Other slice", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      # eight versions, each with a distinct device count so the ordering is stable
      for {version, count} <- Enum.zip(1..8, 8..1//-1) do
        for _ <- 1..count, do: device_on_version(org, product, firmware, "#{version}.0.0")
      end

      {:ok, view, _html} = live(conn, insights_path(org, product))

      assigns = :sys.get_state(view.pid).socket.assigns

      assert length(assigns.firmware_version_slices) == 7
      assert Enum.map(assigns.firmware_version_slices, & &1.label) == ~w(1.0.0 2.0.0 3.0.0 4.0.0 5.0.0 6.0.0 Other)

      # versions 7 and 8, with 2 and 1 devices
      assert assigns.firmware_version_other == %{label: "Other", filter: nil, count: 3, versions: 2}
      assert assigns.firmware_version_count == 8

      assert render(view) =~ "2 other versions"
    end

    test "keeps a lone seventh version as itself rather than an Other of one", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      for {version, count} <- Enum.zip(1..7, 7..1//-1) do
        for _ <- 1..count, do: device_on_version(org, product, firmware, "#{version}.0.0")
      end

      {:ok, view, _html} = live(conn, insights_path(org, product))

      assigns = :sys.get_state(view.pid).socket.assigns

      assert Enum.map(assigns.firmware_version_slices, & &1.label) == ~w(1.0.0 2.0.0 3.0.0 4.0.0 5.0.0 6.0.0 7.0.0)
      refute assigns.firmware_version_other
    end
  end

  describe "filtering the device list from a slice" do
    test "the legend links to the devices list filtered by version", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      device_on_version(org, product, firmware, "1.2.3")

      {:ok, view, _html} = live(conn, insights_path(org, product))

      assert view
             |> element(~s|a[href="#{~p"/org/#{org}/#{product}/devices?firmware_version=1.2.3"}"]|)
             |> has_element?()
    end

    test "clicking a slice navigates to the devices list filtered by version", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      device_on_version(org, product, firmware, "1.2.3")

      {:ok, view, _html} = live(conn, insights_path(org, product))

      render_hook(view, "view-devices-with-firmware-version", %{"version" => "1.2.3"})

      assert_redirect(view, ~p"/org/#{org}/#{product}/devices?firmware_version=1.2.3")
    end

    test "ignores a version which isn't on the chart", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      device_on_version(org, product, firmware, "1.2.3")

      {:ok, view, _html} = live(conn, insights_path(org, product))

      render_hook(view, "view-devices-with-firmware-version", %{"version" => "6.6.6"})

      assert render(view) =~ "Firmware Versions"
    end
  end
end
