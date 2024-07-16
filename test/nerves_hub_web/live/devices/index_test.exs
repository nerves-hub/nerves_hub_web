defmodule NervesHubWeb.Live.Devices.IndexTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Fixtures
  alias NervesHubWeb.Endpoint

  setup %{fixture: %{device: device}} do
    Endpoint.subscribe("device:#{device.id}")
  end

  describe "handle_event" do
    test "filters devices by field", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)

      {:ok, view, html} = live(conn, device_index_path(fixture))
      assert html =~ device2.identifier

      refute render_change(view, "update-filters", %{"device_id" => device.identifier}) =~
               device2.identifier
    end

    test "filters devices by tag", %{conn: conn, fixture: fixture} do
      %{device: _device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware, %{tags: ["filtertest"]})

      {:ok, view, html} = live(conn, device_index_path(fixture))
      assert html =~ device2.identifier

      refute render_change(view, "update-filters", %{"tag" => "filtertest-noshow"}) =~
               device2.identifier

      assert render_change(view, "update-filters", %{"tag" => "filtertest"}) =~
               device2.identifier
    end

    test "filters devices by several tags", %{conn: conn, fixture: fixture} do
      %{device: _device, firmware: firmware, org: org, product: product} = fixture

      device2 =
        Fixtures.device_fixture(org, product, firmware, %{tags: ["filtertest", "testfilter"]})

      {:ok, view, html} = live(conn, device_index_path(fixture))
      assert html =~ device2.identifier

      refute render_change(view, "update-filters", %{"tag" => "filtertest-noshow"}) =~
               device2.identifier

      assert render_change(view, "update-filters", %{"tag" => "filtertest"}) =~
               device2.identifier

      assert render_change(view, "update-filters", %{"tag" => "filtertest, testfilter"}) =~
               device2.identifier
    end

    test "filters devices with no tags", %{conn: conn, fixture: fixture} do
      %{device: _device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware, %{tags: nil})

      {:ok, view, html} = live(conn, device_index_path(fixture))
      assert html =~ device2.identifier

      refute render_change(view, "update-filters", %{"tag" => "doesntmatter"}) =~
               device2.identifier
    end
  end

  describe "bulk actions" do
    test "changes tags", %{conn: conn, fixture: fixture} do
      %{device: device, org: org, product: product} = fixture

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("h1", text: "Devices")
      |> assert_has("span", text: "beta")
      |> assert_has("span", text: "beta-edge")
      |> unwrap(fn view ->
        render_change(view, "select", %{"id" => device.id})
      end)
      |> fill_in("Set tag(s) to:", with: "moussaka")
      |> click_button("Set")
      |> assert_has("span", text: "moussaka")
    end
  end

  def device_index_path(%{org: org, product: product}) do
    ~p"/org/#{org.name}/#{product.name}/devices"
  end
end
