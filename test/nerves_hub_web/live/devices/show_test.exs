defmodule NervesHubWeb.Live.Devices.ShowTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  import Phoenix.ChannelTest

  alias NervesHub.AuditLogs
  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Devices.Metrics
  alias NervesHub.Firmwares
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.Repo
  alias NervesHubWeb.Endpoint
  alias Phoenix.Channel.Server, as: ChannelServer
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
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settings")
      |> assert_has("h1", text: device.identifier)
      |> click_button("Delete device")
      |> assert_path("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settings")
      |> assert_has("div", text: "Device is deleted and must be restored to use.")

      device = Devices.get_device(device.id)

      refute is_nil(device.deleted_at)
    end

    test "reboot allowed", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture
      {:ok, view, _html} = live(conn, device_show_path(fixture))

      before_audit_count = AuditLogs.logs_for(device) |> length()

      _view = render_change(view, :reboot, %{})
      assert_broadcast("reboot", %{})

      after_audit_count = AuditLogs.logs_for(device) |> length()

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
    test "device connecting updates the UI", %{conn: conn, fixture: fixture} do
      conn
      |> visit(device_show_path(fixture))
      |> assert_has("svg[data-connection-status=unknown]")
      |> unwrap(fn view ->
        {:ok, connection} =
          Connections.device_connecting(fixture.device, fixture.device.product_id)

        :ok = Connections.device_connected(fixture.device, connection.id)
        render(view)
      end)
      |> assert_has("svg[data-connection-status=connected]")
    end

    test "connection:status updates assigns when coming online", %{
      conn: conn,
      fixture: fixture,
      device: device,
      deployment_group: deployment_group
    } do
      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(
          deployment_group,
          %{is_active: true},
          fixture.user
        )

      # Set device status to :provisioned for deployment group eligibility
      %{status: :provisioned} = device = Devices.set_as_provisioned!(device)

      {:ok, connection} = Connections.device_connecting(device, device.product_id)
      :ok = Connections.device_connected(device, connection.id)

      # mismatch device and deployment group firmware so "Send Update" form doesn't display
      original_firmware_platform = device.firmware_metadata.platform

      updated_firmware_metadata =
        device.firmware_metadata
        |> Map.from_struct()
        |> Map.put(:platform, "foobar")

      {:ok, device} =
        Devices.update_firmware_metadata(device, updated_firmware_metadata, :unknown, false)

      conn
      |> visit(device_show_path(fixture))
      |> assert_has("svg[data-connection-status=connected]")
      |> refute_has("div", text: "Assigned Deployment Group")
      |> refute_has("span", text: "Update available")
      |> refute_has("option", text: "Select a version")
      |> assert_has("div", text: "No device health information has been received.")
      |> refute_has("div", text: "CPU use")
      |> unwrap(fn view ->
        :ok = Connections.device_disconnected(device, connection.id)
        render(view)
      end)
      |> assert_has("svg[data-connection-status=disconnected]")
      |> unwrap(fn view ->
        restored_firmware_metadata =
          device.firmware_metadata
          |> Map.from_struct()
          |> Map.put(:platform, original_firmware_platform)
          |> Map.put(:uuid, "foobar123")

        {:ok, device} =
          Devices.update_firmware_metadata(device, restored_firmware_metadata, :unknown, false)

        device = Devices.update_deployment_group(device, deployment_group)

        {:ok, _} = Metrics.save_metrics(device.id, %{"cpu_usage_percent" => 22})

        {:ok, connection} = Connections.device_connecting(device, device.product_id)
        :ok = Connections.device_connected(device, connection.id)

        topic = "device:#{device.id}:extensions"
        ChannelServer.broadcast!(NervesHub.PubSub, topic, "health_check_report", %{})

        render(view)
      end)
      |> assert_has("div", text: "Assigned deployment group:")
      |> assert_has("span", text: "Update available")
      |> assert_has("option", text: "Select a version")
      |> refute_has("div", text: "No device health information has been received.")
      |> assert_has("div", text: "22%")
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
      |> assert_has("div", text: "Updating firmware 50%")
    end

    test "complete fwup progress", %{conn: conn, org: org, product: product, device: device} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> unwrap(fn view ->
        send(view.pid, %Broadcast{event: "fwup_progress", payload: %{percent: 50}})
        render(view)
      end)
      |> assert_has("div", text: "Updating firmware 50%")
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
      |> assert_has("div", text: "Location")
      |> assert_has("div", text: "Device maps haven't been enabled on your platform.")
    end

    test "location information is empty", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      {:ok, connection} = Connections.device_connecting(device, device.product_id)
      :ok = Connections.device_connected(device, connection.id)
      :ok = Connections.merge_update_metadata(connection.id, %{"location" => %{}})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("div", text: "Location")
      |> assert_has("div", text: "No location information found.")
    end

    test "location information is blank (nil)", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      {:ok, connection} = Connections.device_connecting(device, device.product_id)
      :ok = Connections.device_connected(device, connection.id)
      :ok = Connections.merge_update_metadata(connection.id, %{"location" => %{"latitude" => nil, "longitude" => nil}})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("div", text: "Location")
      |> assert_has("div", text: "The location coordinates are not currently available.")
    end

    test "location information is blank (empty strings)", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      {:ok, connection} = Connections.device_connecting(device, device.product_id)
      :ok = Connections.device_connected(device, connection.id)
      :ok = Connections.merge_update_metadata(connection.id, %{"location" => %{"latitude" => "", "longitude" => ""}})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("div", text: "Location")
      |> assert_has("div", text: "The location coordinates are not currently available.")
    end

    test "a location error occurred", %{conn: conn, org: org, product: product, device: device} do
      metadata = %{
        "location" => %{"error_code" => "BOOP", "error_description" => "BEEP"}
      }

      {:ok, connection} = Connections.device_connecting(device, device.product_id)
      :ok = Connections.device_connected(device, connection.id)
      :ok = Connections.merge_update_metadata(connection.id, metadata)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("div", text: "Location")
      |> assert_has("div", text: "An error occurred during location resolution : BOOP")
      |> assert_has("div", text: "BEEP")
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

      {:ok, connection} = Connections.device_connecting(device, device.product_id)
      :ok = Connections.device_connected(device, connection.id)
      :ok = Connections.merge_update_metadata(connection.id, metadata)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("div", text: "Location")
      |> assert_has(~s(div#device-location-map[data-center-lat="-41.3159"]))
      |> assert_has(~s(div#device-location-map[data-center-lng="174.8185"]))
    end
  end

  describe "device health" do
    test "no device health", %{conn: conn, org: org, product: product, device: device} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("div", text: "Health")
      |> assert_has("div", text: "No device health information has been received.")
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
      |> assert_has("div", text: "Alarms")
      |> assert_has("code", text: "SomeAlarm")
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
      |> assert_has("div", text: "No Alarms Received")

      assert {:ok, _} =
               NervesHub.Devices.save_device_health(%{
                 "device_id" => device.id,
                 "data" => %{"alarms" => %{}}
               })

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("div", text: "Health")
      |> assert_has("div", text: "No Alarms Received")
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
      |> assert_has("span", text: "0.0", exact: true, count: 3)
      |> assert_has("div", text: "Memory used")
      |> assert_has("span", text: "100MB")
      |> assert_has("span", text: "60%")
      |> assert_has("div", text: "CPU")
      |> assert_has("span", text: "30°")
    end

    test "cpu temp missing", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      metrics = %{
        "load_15min" => 1.23,
        "load_1min" => 4.56,
        "load_5min" => 7.89,
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
      |> assert_has("span", text: "1.23")
      |> assert_has("span", text: "4.56")
      |> assert_has("span", text: "7.89")
      |> assert_has("div", text: "Memory used")
      |> assert_has("span", text: "100MB")
      |> assert_has("span", text: "60%")
      |> assert_has("span", text: "Last updated:")
      |> assert_has("time", text: "now")
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

      conn =
        conn
        |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
        |> assert_has("h1", text: device.identifier)
        |> assert_has("option[value=\"#{firmware.uuid}\"]", text: firmware.version)

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn
      |> assert_has("option[value=\"#{new_firmware.uuid}\"]", text: new_firmware.version)
      |> assert_has("p",
        text:
          "New firmware #{new_firmware.version} (#{String.slice(new_firmware.uuid, 0..7)}) is available for selection"
      )
    end

    test "updates when firmware is deleted", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      org_key: org_key,
      tmp_dir: tmp_dir
    } do
      firmware_1 = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      firmware_2 = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      conn =
        conn
        |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
        |> assert_has("h1", text: device.identifier)
        |> assert_has("option[value=\"#{firmware_1.uuid}\"]", text: firmware_1.version)
        |> assert_has("option[value=\"#{firmware_2.uuid}\"]", text: firmware_2.version)

      Firmwares.delete_firmware(firmware_1)

      conn
      |> assert_has("option[value=\"#{firmware_2.uuid}\"]", text: firmware_2.version)
      |> refute_has("option[value=\"#{firmware_1.uuid}\"]", text: firmware_1.version)
      |> assert_has("p",
        text:
          "Firmware #{firmware_1.version} (#{String.slice(firmware_1.uuid, 0..7)}) has been deleted by another user."
      )
    end
  end

  describe "available update" do
    test "no available update exists", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      deployment_group: deployment_group
    } do
      device =
        device
        |> Ecto.Changeset.change(%{deployment_id: deployment_group.id})
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
      deployment_group: deployment_group,
      org_key: org_key,
      tmp_dir: tmp_dir
    } do
      device =
        device
        |> Ecto.Changeset.change(%{deployment_id: deployment_group.id, status: :provisioned})
        |> Repo.update!()

      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      {:ok, connection} =
        Connections.device_connecting(device, device.product_id)

      :ok = Connections.device_connected(device, connection.id)

      deployment_group
      |> Ecto.Changeset.change(%{firmware_id: firmware.id, is_active: true})
      |> Repo.update!()

      NervesHubWeb.Endpoint.subscribe("device:#{device.id}")

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("span", text: "Update available")
      |> click_button("Skip the queue")
      |> assert_has("div", text: "Pushing available firmware update")

      assert Repo.aggregate(InflightUpdate, :count) == 1

      topic = "device:#{device.id}"

      assert_receive %Broadcast{
        topic: ^topic,
        event: "update"
      }
    end

    test "available update exists but deployment is not active", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      deployment_group: deployment_group,
      org_key: org_key,
      tmp_dir: tmp_dir
    } do
      device =
        device
        |> Ecto.Changeset.change(%{deployment_id: deployment_group.id})
        |> Repo.update!()

      {:ok, connection} =
        Connections.device_connecting(device, device.product_id)

      :ok = Connections.device_connected(device, connection.id)

      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      deployment_group
      |> Ecto.Changeset.change(%{firmware_id: firmware.id, is_active: false})
      |> Repo.update!()

      NervesHubWeb.Endpoint.subscribe("device:#{device.id}")

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> refute_has("span", text: "Update available")
      |> refute_has("button", text: "Skip the queue")

      assert Repo.aggregate(InflightUpdate, :count) == 0
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
      device: device,
      user: user
    } do
      {:ok, script} =
        NervesHub.Scripts.create(product, user, %{name: "MOTD", text: "NervesMOTD.print()"})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("div", text: "Support Scripts")
      |> assert_has("div", text: "MOTD")
      |> assert_has("button[phx-value-id=\"#{script.id}\"]")
    end
  end

  describe "clearing deployment" do
    test "clears deployment and eligible deployments list is refreshed", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      deployment_group: deployment_group
    } do
      device =
        device
        |> Ecto.Changeset.change(%{deployment_id: deployment_group.id, status: :provisioned})
        |> Repo.update!()

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> unwrap(fn view ->
        render_change(view, "remove-from-deployment-group")
      end)
      |> assert_has("select#deployment_group option", text: "Select a deployment group")

      assert_receive %Broadcast{event: "deployment_updated"}

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
    test "displays and sets product deployments for unprovisioned device", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      deployment_group: deployment_group
    } do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("select#deployment_group option", text: "Select a deployment group")
      |> unwrap(fn view ->
        render_change(view, "set-deployment-group", %{"deployment_id" => deployment_group.id})
      end)
      |> assert_has("span",
        text:
          "Please note: The device will be removed from the deployment group upon connection if the arch and platform don't match."
      )
    end

    test "sets deployment, creates audit, and broadcasts to the devices channel", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      deployment_group: deployment_group
    } do
      # Set device status to :provisioned for deployment eligibility
      %{status: :provisioned} = Devices.set_as_provisioned!(device)

      assert Enum.empty?(AuditLogs.logs_for(device))

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("option", text: "Select a deployment group")
      |> select("Deployment Group", exact_option: false, option: deployment_group.name)
      |> click_button("Assign")
      |> refute_has("div", text: "No assigned deployment group")

      assert Repo.reload(device) |> Map.get(:deployment_id)
      assert length(AuditLogs.logs_for(device)) == 1

      device_topic = "device:#{device.id}"
      assert_receive %Broadcast{topic: ^device_topic, event: "deployment_updated"}
    end

    test "'no eligible deployments' text displays properly", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      deployment_group: deployment_group
    } do
      # Set device status to :provisioned for deployment eligibility
      %{status: :provisioned} = Devices.set_as_provisioned!(device)
      _ = Repo.delete!(deployment_group)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("span",
        text: "No deployment groups match the devices platform and architecture."
      )
      |> refute_has("option", text: "Select a deployment group")
    end
  end

  def device_show_path(%{device: device, org: org, product: product}) do
    ~p"/org/#{org}/#{product}/devices/#{device}"
  end
end
