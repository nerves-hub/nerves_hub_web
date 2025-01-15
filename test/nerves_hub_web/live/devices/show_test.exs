defmodule NervesHubWeb.Live.Devices.ShowTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  import Phoenix.ChannelTest

  alias NervesHub.AuditLogs
  alias NervesHub.Deployments
  alias NervesHub.Devices
  alias NervesHub.Devices.Metrics
  alias NervesHub.Fixtures
  alias NervesHub.Repo
  alias NervesHubWeb.Endpoint

  alias Phoenix.Socket.Broadcast

  setup %{fixture: %{device: device}} do
    Endpoint.subscribe("device:#{device.id}")
  end

  describe "render liveview" do
    test "render when device has no firmware", %{
      conn: conn,
      org: org,
      product: product
    } do
      {:ok, device} =
        Devices.create_device(%{
          org_id: org.id,
          product_id: product.id,
          identifier: "no-firmware-device"
        })

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: "no-firmware-device")
    end
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

      assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} =
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

      Devices.Connections.device_connected(fixture.device.id)
      send(view.pid, %Broadcast{event: "connection:change", payload: %{status: "online"}})

      assert render(view) =~ "online"
    end

    test "connection:status updates assigns when coming online", %{
      conn: conn,
      fixture: fixture,
      device: device,
      deployment: deployment
    } do
      {:ok, deployment} = Deployments.update_deployment(deployment, %{is_active: true})

      # mismatch device and deployment firmware so "Send Update" form doesn't display
      original_firmware_platform = device.firmware_metadata.platform

      updated_firmware_metadata =
        device.firmware_metadata
        |> Map.from_struct()
        |> Map.put(:platform, "foobar")

      {:ok, device} = Devices.update_firmware_metadata(device, updated_firmware_metadata)

      conn
      |> visit(device_show_path(fixture))
      |> refute_has("div", text: "Assigned Deployment")
      |> refute_has("span", text: "Update available")
      |> refute_has("option", text: "Select a version")
      |> assert_has("a.disabled", text: "Console")
      |> assert_has("div", text: "No health information has been received for this device.")
      |> refute_has("div", text: "CPU use")
      |> unwrap(fn view ->
        # stub tracker so link to console isn't disabled
        expect(NervesHub.Tracker, :console_active?, fn _device -> true end)

        restored_firmware_metadata =
          device.firmware_metadata
          |> Map.from_struct()
          |> Map.put(:platform, original_firmware_platform)
          |> Map.put(:uuid, "foobar123")

        {:ok, device} = Devices.update_firmware_metadata(device, restored_firmware_metadata)

        _device = Devices.update_deployment(device, deployment)

        {:ok, _} = Metrics.save_metrics(device.id, %{"cpu_usage_percent" => 22})

        send(view.pid, %Broadcast{event: "connection:status", payload: %{status: "online"}})
        render(view)
      end)
      |> assert_has("div", text: "Assigned Deployment")
      |> assert_has("span", text: "Update available")
      |> assert_has("option", text: "Select a version")
      |> refute_has("a.disabled", text: "Console")
      |> refute_has("div", text: "No health information has been received for this device.")
      |> assert_has("div", text: "CPU use")
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
      |> assert_has("div", text: "No health information has been received for this device.")
    end

    test "has active alarms", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      device_health = %{
        "device_id" => device.id,
        "data" => %{"alarms" => %{"SomeAlarm" => "Some description"}}
      }

      assert {:ok, _} = NervesHub.Devices.save_device_health(device_health)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("div", text: "Health")
      |> assert_has("div", text: "Active Alarms")
      |> assert_has("span", text: "SomeAlarm")
    end

    test "has no active alarms", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("div", text: "Health")
      |> assert_has("div", text: "No active alarms")

      assert {:ok, _} =
               NervesHub.Devices.save_device_health(%{
                 "device_id" => device.id,
                 "data" => %{"alarms" => %{}}
               })

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("div", text: "Health")
      |> assert_has("div", text: "No active alarms")
    end

    test "full set of metrics", %{
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
        "mem_size_mb" => 7892,
        "mem_used_mb" => 100,
        "mem_used_percent" => 60
      }

      assert {:ok, 7} = Metrics.save_metrics(device.id, metrics)

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
        "mem_size_mb" => 7892,
        "mem_used_mb" => 100,
        "mem_used_percent" => 60
      }

      assert {:ok, 6} = Metrics.save_metrics(device.id, metrics)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("div", text: "Health")
      |> assert_has("div", text: "Load avg")
      |> assert_has("div", text: "0.0 | 0.0 | 0.0")
      |> assert_has("div", text: "Memory used")
      |> assert_has("div", text: "100MB (60%)")
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
      |> Ecto.Changeset.change(%{firmware_id: firmware.id, is_active: true})
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

    test "available update exists but deployment is not active", %{
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
      |> Ecto.Changeset.change(%{firmware_id: firmware.id, is_active: false})
      |> Repo.update!()

      NervesHubWeb.Endpoint.subscribe("device:#{device.id}")

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> refute_has("span", text: "Update available")

      assert Repo.aggregate(NervesHub.Devices.InflightUpdate, :count) == 0
    end
  end

  describe "support scripts" do
    test "no scripts available", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> refute_has("h3", text: "Support Scripts")
    end

    test "list scripts", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      {:ok, _command} =
        NervesHub.Scripts.create(product, %{name: "MOTD", text: "NervesMOTD.print()"})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h3", text: "Support Scripts")
      |> assert_has("div", text: "MOTD")
      |> assert_has("button", text: "Run")
    end
  end

  describe "clearing deployment" do
    test "clears deployment and eligible deployments list is refreshed", %{
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
      |> unwrap(fn view ->
        render_change(view, "remove-from-deployment")
      end)
      |> assert_has("div", text: "Eligible Deployments")

      refute Repo.reload(device) |> Map.get(:deployment_id)
    end

    test "cannot clear deployment if no deployment is set", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> refute_has("a", text: "Remove From Deployment")
    end
  end

  describe "setting deployment" do
    test "sets deployment and creates audit", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      deployment: deployment
    } do
      assert Enum.empty?(AuditLogs.logs_for(device))

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("div", text: "Eligible Deployment")
      |> unwrap(fn view ->
        render_change(view, "set-deployment", %{"deployment_id" => deployment.id})
      end)
      |> assert_has("div", text: "Assigned Deployment")

      assert Repo.reload(device) |> Map.get(:deployment_id)
      assert length(AuditLogs.logs_for(device)) == 1
    end

    test "'no eligible deployments' text displays properly", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      deployment: deployment
    } do
      _ = Repo.delete!(deployment)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("div", text: "No Eligible Deployments")
    end
  end

  def device_show_path(%{device: device, org: org, product: product}) do
    ~p"/org/#{org.name}/#{product.name}/devices/#{device.identifier}"
  end
end
