defmodule NervesHubWeb.Live.Devices.ShowTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  import Phoenix.ChannelTest

  alias NervesHub.AuditLogs
  alias NervesHub.Devices
  alias NervesHub.Repo
  alias NervesHubWeb.Endpoint

  alias Phoenix.Socket.Broadcast

  setup %{fixture: %{device: device}} do
    Endpoint.subscribe("device:#{device.id}")
  end

  describe "handle_event" do
    test "delete device", %{conn: conn, org: org, product: product, device: device} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> click_button("Delete")
      |> assert_path("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("div.alert div center", text: "Device is deleted and must be restored to use")

      device = Devices.get_device(device.id)

      refute is_nil(device.deleted_at)
    end

    test "reboot allowed", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture
      {:ok, view, _html} = live(conn, device_show_path(fixture))

      before_audit_count = AuditLogs.logs_for(device) |> length

      _view = render_change(view, :reboot, %{})
      assert_broadcast("reboot", %{})

      after_audit_count = AuditLogs.logs_for(device) |> length

      assert after_audit_count == before_audit_count + 1
    end

    test "reboot blocked", %{conn: conn, fixture: fixture} do
      Repo.preload(fixture.user, :org_users)
      |> Map.get(:org_users)
      |> Enum.map(&NervesHub.Accounts.change_org_user_role(&1, :view))

      {:ok, view, _html} = live(conn, device_show_path(fixture))

      Process.flag(:trap_exit, true)

      assert {{%NervesHub.Errors.Unauthorized{}, _}, _} =
               catch_exit(render_change(view, :reboot, %{}))
    end
  end

  describe "handle_info" do
    test "presence_diff with no change", %{conn: conn, fixture: fixture} do
      payload = %{joins: %{}, leaves: %{}}
      {:ok, view, html} = live(conn, device_show_path(fixture))

      assert html =~ "offline"
      send(view.pid, %Broadcast{event: "presence_diff", payload: payload})
      assert render(view) =~ "offline"
    end

    test "presence_diff with changes", %{conn: conn, fixture: fixture} do
      {:ok, view, html} = live(conn, device_show_path(fixture))

      assert html =~ "offline"

      send(view.pid, %Broadcast{event: "connection:change", payload: %{status: "online"}})

      assert render(view) =~ "online"
    end
  end

  describe "geo location" do
    setup do
      Application.put_env(:nerves_hub, :mapbox_access_token, "abc")
    end

    test "mapbox not enabled", %{conn: conn, org: org, product: product, device: device} do
      Application.put_env(:nerves_hub, :mapbox_access_token, nil)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("span", text: "Device location")
      |> assert_has("span", text: "Device maps haven't been enabled on your platform.")
    end

    test "no location information found attached to the device", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("span", text: "Device location")
      |> assert_has("span", text: "No location was found for the device.")
    end

    test "location information is empty", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      Devices.update_device(device, %{connection_metadata: %{"location" => %{}}})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("span", text: "Device location")
      |> assert_has("span", text: "No location was found for the device.")
    end

    test "ip address reserved", %{conn: conn, org: org, product: product, device: device} do
      metadata = %{
        "request_ip" => "127.0.0.1",
        "location" => %{"error_code" => "IP_ADDRESS_RESERVED"}
      }

      Devices.update_device(device, %{connection_metadata: metadata})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("span", text: "Device location")
      |> assert_has("span", text: "The IP address is reporting as 127.0.0.1")
    end

    test "the happy path", %{conn: conn, org: org, product: product, device: device} do
      metadata = %{
        "location" => %{
          "latitude" => "-41.3159",
          "longitude" => "174.8185",
          "accuracy_radius" => "20"
        }
      }

      Devices.update_device(device, %{connection_metadata: metadata})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("span", text: "Device location")
      |> assert_has(
        "img[src=\"https://api.mapbox.com/styles/v1/mapbox/satellite-streets-v12/static/174.8185,-41.3159,10,0/463x250@2x?access_token=abc\"]"
      )
    end
  end

  def device_show_path(%{device: device, org: org, product: product}) do
    ~p"/org/#{org.name}/#{product.name}/devices/#{device.identifier}"
  end
end
