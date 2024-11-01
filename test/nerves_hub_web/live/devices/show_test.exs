defmodule NervesHubWeb.Live.Devices.ShowTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  import Phoenix.ChannelTest

  alias NervesHub.AuditLogs
  alias NervesHub.Devices
  alias NervesHub.Devices.Metrics
  alias NervesHub.Fixtures
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

  describe "fwup progress" do
    test "no fwup progress", %{conn: conn, org: org, product: product, device: device} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> refute_has("div", text: "Progress")
      |> refute_has("div.progress")
    end

    test "some fwup progress", %{conn: conn, org: org, product: product, device: device} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> unwrap(fn view ->
        send(view.pid, %Broadcast{event: "fwup_progress", payload: %{percent: 50}})
        render(view)
      end)
      |> assert_has("div", text: "Progress")
      |> assert_has("div.progress", text: "50%")
    end

    test "complete fwup progress", %{conn: conn, org: org, product: product, device: device} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> unwrap(fn view ->
        send(view.pid, %Broadcast{event: "fwup_progress", payload: %{percent: 50}})
        render(view)
      end)
      |> assert_has("div", text: "Progress")
      |> assert_has("div.progress", text: "50%")
      |> unwrap(fn view ->
        send(view.pid, %Broadcast{event: "fwup_progress", payload: %{percent: 100}})
        render(view)
      end)
      |> refute_has("div", text: "Progress")
      |> refute_has("div.progress")
      |> assert_has("div", text: "Update complete: The device will reboot shortly.")
    end

    test "hides flash after the device has restarted", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> unwrap(fn view ->
        send(view.pid, %Broadcast{event: "fwup_progress", payload: %{percent: 100}})
        render(view)
      end)
      |> refute_has("div", text: "Progress")
      |> refute_has("div.progress")
      |> assert_has("div", text: "Update complete: The device will reboot shortly.")
      |> unwrap(fn view ->
        send(view.pid, %Broadcast{
          topic: "device:#{device.identifier}:internal",
          event: "connection:change",
          payload: %{status: "offline"}
        })

        render(view)
      end)
      |> assert_has("div", text: "Update complete: The device will reboot shortly.")
      |> unwrap(fn view ->
        send(view.pid, %Broadcast{
          topic: "device:#{device.identifier}:internal",
          event: "connection:change",
          payload: %{status: "online"}
        })

        render(view)
      end)
      |> refute_has("div", text: "Update complete: The device will reboot shortly.")
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
      |> assert_has("span", text: "No location information found.")
    end

    test "a location error occurred", %{conn: conn, org: org, product: product, device: device} do
      metadata = %{
        "location" => %{"error_code" => "BOOP", "error_description" => "BEEP"}
      }

      Devices.update_device(device, %{connection_metadata: metadata})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("span", text: "Device location")
      |> assert_has("span", text: "An error occurred during location resolution : BOOP")
      |> assert_has("span", text: "BEEP")
    end

    test "the happy path", %{conn: conn, org: org, product: product, device: device} do
      metadata = %{
        "location" => %{
          "latitude" => "-41.3159",
          "longitude" => "174.8185",
          "accuracy" => "20",
          "source" => "geoip"
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

  describe "device health" do
    test "no device health", %{conn: conn, org: org, product: product, device: device} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("div", text: "Health")
      |> assert_has("div", text: "No health information have been received for this device.")
    end

    test "full set of information", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      metrics = %{
        "cpu_temp" => 30,
        "load_15min" => 0.00,
        "load_1min" => 0.00,
        "load_5min" => 0.00,
        "size_mb" => 7892,
        "used_mb" => 100,
        "used_percent" => 60
      }

      assert {7, nil} = Metrics.save_metrics(device.id, metrics)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("div", text: "Health")
      |> assert_has("div", text: "Load avg")
      |> assert_has("div", text: "0.0 | 0.0 | 0.0")
      |> assert_has("div", text: "Memory used")
      |> assert_has("div", text: "100MB (60%)")
      |> assert_has("div", text: "CPU")
      |> assert_has("div", text: "30")
    end

    test "cpu temp missing", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      metrics = %{
        "load_15min" => 0.00,
        "load_1min" => 0.00,
        "load_5min" => 0.00,
        "size_mb" => 7892,
        "used_mb" => 100,
        "used_percent" => 60
      }

      assert {6, nil} = Metrics.save_metrics(device.id, metrics)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("div", text: "Health")
      |> assert_has("div", text: "Load avg")
      |> assert_has("div", text: "0.0 | 0.0 | 0.0")
      |> assert_has("div", text: "Memory used")
      |> assert_has("div", text: "100MB (60%)")
      |> assert_has("div", text: "CPU")
      |> assert_has("div", text: "Not reported")
      |> assert_has("span", text: "Last reported :")
      |> assert_has("time", text: "ago")
    end
  end

  describe "firmware selection" do
    test "updates when new firmware is available", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      org_key: org_key,
      tmp_dir: tmp_dir
    } do
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      session =
        conn
        |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
        |> assert_has("h1", text: device.identifier)
        |> assert_has("option[value=\"#{firmware.uuid}\"]", text: firmware.version)

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      assert_has(session, "option[value=\"#{new_firmware.uuid}\"]", text: new_firmware.version)
    end
  end

  describe "available update" do
    test "no available update exists", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      deployment: deployment
    } do
      device =
        device
        |> Ecto.Changeset.change(%{deployment_id: deployment.id})
        |> Repo.update!()

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> refute_has("span", text: "Update available")
    end

    test "available update exists", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      deployment: deployment,
      org_key: org_key,
      tmp_dir: tmp_dir
    } do
      device =
        device
        |> Ecto.Changeset.change(%{deployment_id: deployment.id})
        |> Repo.update!()

      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      deployment
      |> Ecto.Changeset.change(%{firmware_id: firmware.id})
      |> Repo.update!()

      NervesHubWeb.Endpoint.subscribe("device:#{device.id}")

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("span", text: "Update available")
      |> click_button("Send available update")
      |> assert_has("div", text: "Pushing available firmware update")

      assert Repo.aggregate(NervesHub.Devices.InflightUpdate, :count) == 1

      assert_receive %Phoenix.Socket.Broadcast{event: "deployments/update"}
    end
  end

  def device_show_path(%{device: device, org: org, product: product}) do
    ~p"/org/#{org.name}/#{product.name}/devices/#{device.identifier}"
  end
end
