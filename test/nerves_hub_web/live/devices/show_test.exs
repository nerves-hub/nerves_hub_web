defmodule NervesHubWeb.Live.Devices.ShowTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  import Ecto.Query, only: [where: 2]
  import Phoenix.ChannelTest

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Org
  alias NervesHub.AuditLogs
  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Devices.Metrics
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Repo
  alias NervesHubWeb.Endpoint
  alias Phoenix.Channel.Server, as: ChannelServer
  alias Phoenix.Socket.Broadcast

  setup %{fixture: %{device: device}} do
    Endpoint.subscribe("device:#{device.id}")
  end

  describe "shows device" do
    test "when device has no firmware", %{
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

  describe "who is currently viewing the device page" do
    setup %{fixture: %{org: org}} do
      # https://hexdocs.pm/phoenix/Phoenix.Presence.html#module-testing-with-presence
      on_exit(fn ->
        for pid <- NervesHubWeb.Presence.fetchers_pids() do
          ref = Process.monitor(pid)
          assert_receive {:DOWN, ^ref, _, _, _}, 1000
        end
      end)

      user_two = Fixtures.user_fixture()
      {:ok, _} = Accounts.add_org_user(org, user_two, %{role: :view})

      {:ok, %{user_two: user_two}}
    end

    test "only the current user", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user
    } do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("#present-users > #presences-#{user.id} > span", text: user_initials(user))
    end

    test "two users, same device", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user,
      user_two: user_two
    } do
      token_two = NervesHub.Accounts.create_user_session_token(user_two)

      conn_two =
        build_conn()
        |> init_test_session(%{"user_token" => token_two})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("#present-users > #presences-#{user.id} > span", text: user_initials(user))

      conn_two
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("#present-users > #presences-#{user.id} > span", text: user_initials(user))
      |> assert_has("#present-users > #presences-#{user_two.id} > span",
        text: user_initials(user_two)
      )
    end

    test "two users, different devices", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user,
      user_two: user_two
    } do
      {:ok, firmware} = Firmwares.get_firmware_by_product_id_and_uuid(device.product_id, device.firmware_metadata.uuid)
      device_two = Fixtures.device_fixture(org, product, firmware)

      token_two = NervesHub.Accounts.create_user_session_token(user_two)

      conn_two =
        build_conn()
        |> init_test_session(%{"user_token" => token_two})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("h1", text: device.identifier)
      |> assert_has("#present-users > #presences-#{user.id} > span", text: user_initials(user))

      conn_two
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device_two.identifier}")
      |> assert_has("h1", text: device_two.identifier)
      |> assert_has("#present-users > #presences-#{user_two.id} > span",
        text: user_initials(user_two)
      )
      |> refute_has("#present-users > #presences-#{user.id} > span", text: user_initials(user))
    end

    defp user_initials(user) do
      user.name
      |> String.split()
      |> Enum.map_join("", fn w -> String.at(w, 0) |> String.upcase() end)
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
      |> assert_has("div", text: "The location coordinates are invalid and can't be displayed.")
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
      |> assert_has("div", text: "The location coordinates are invalid and can't be displayed.")
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

  describe "deployment group" do
    test "eligible deployment groups are listed when device is provisioned", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user,
      deployment_group: deployment_group,
      fixture: %{firmware: firmware},
      tmp_dir: tmp_dir
    } do
      _ = Devices.set_as_provisioned!(device)
      org_key2 = Fixtures.org_key_fixture(org, user, tmp_dir)

      mismatched_firmware =
        Fixtures.firmware_fixture(org_key2, product, %{platform: "Vulture", architecture: "arm", dir: tmp_dir})

      mismatched_firmware_deployment_group =
        Fixtures.deployment_group_fixture(mismatched_firmware, %{
          name: "Vulture Deployment 2025"
        })

      deployment_group2 =
        Fixtures.deployment_group_fixture(firmware, %{name: "Beta Deployment"})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("option", text: deployment_group.name)
      |> assert_has("option", text: deployment_group2.name)
      |> refute_has("option", text: mismatched_firmware_deployment_group.name)
    end

    test "product's deployment groups are listed when device is registered", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user,
      deployment_group: deployment_group,
      fixture: %{firmware: firmware},
      tmp_dir: tmp_dir
    } do
      assert device.status == :registered
      org_key2 = Fixtures.org_key_fixture(org, user, tmp_dir)
      product2 = Fixtures.product_fixture(user, org, %{name: "Product 123"})
      firmware2 = Fixtures.firmware_fixture(org_key2, product2, %{dir: tmp_dir})

      deployment_group_from_product2 =
        Fixtures.deployment_group_fixture(firmware2, %{
          name: "Vulture Deployment 2025"
        })

      deployment_group2 =
        Fixtures.deployment_group_fixture(firmware, %{name: "Beta Deployment"})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("option", text: deployment_group.name)
      |> assert_has("option", text: deployment_group2.name)
      |> refute_has("option", text: deployment_group_from_product2.name)
    end

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

  describe "skip the queue when there is an available update" do
    test "only shows the button if an update is available", %{
      conn: conn,
      org: org,
      org_key: org_key,
      product: product,
      device: device,
      deployment_group: deployment_group,
      tmp_dir: tmp_dir
    } do
      assert device.updates_enabled

      device = Devices.update_deployment_group(device, deployment_group)
      {:ok, connection} = Connections.device_connecting(device, device.product_id)
      :ok = Connections.device_connected(device, connection.id)
      device = Devices.set_as_provisioned!(device)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> refute_has("button", text: "Skip the queue")

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      DeploymentGroup
      |> where(id: ^deployment_group.id)
      |> Repo.update_all(set: [is_active: true, firmware_id: new_firmware.id])

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("button", text: "Skip the queue")
    end

    test "allows a device to be sent the available update immediately, using the default url config", %{
      conn: conn,
      org: org,
      org_key: org_key,
      product: product,
      device: device,
      deployment_group: deployment_group,
      tmp_dir: tmp_dir
    } do
      assert device.updates_enabled

      device = Devices.update_deployment_group(device, deployment_group)
      {:ok, connection} = Connections.device_connecting(device, device.product_id)
      :ok = Connections.device_connected(device, connection.id)
      device = Devices.set_as_provisioned!(device)

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      DeploymentGroup
      |> where(id: ^deployment_group.id)
      |> Repo.update_all(set: [is_active: true, firmware_id: new_firmware.id])

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> click_button("Skip the queue")

      %{version: version, architecture: architecture, platform: platform} = new_firmware

      assert_receive %Broadcast{
        payload: %{
          firmware_url: firmware_url,
          firmware_meta: %{
            version: ^version,
            architecture: ^architecture,
            platform: ^platform
          }
        },
        event: "update"
      }

      assert String.starts_with?(firmware_url, "http://localhost:1234")

      assert Repo.reload(device) |> Map.get(:updates_enabled)
    end

    test "allows a device to be sent the available update immediately, using the available Org `firmware_proxy_url` setting",
         %{
           conn: conn,
           org: org,
           org_key: org_key,
           product: product,
           device: device,
           deployment_group: deployment_group,
           tmp_dir: tmp_dir
         } do
      Org
      |> where(id: ^org.id)
      |> Repo.update_all(set: [settings: %Org.Settings{firmware_proxy_url: "https://files.customer.com/download"}])

      assert device.updates_enabled

      device = Devices.update_deployment_group(device, deployment_group)
      {:ok, connection} = Connections.device_connecting(device, device.product_id)
      :ok = Connections.device_connected(device, connection.id)
      device = Devices.set_as_provisioned!(device)

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      DeploymentGroup
      |> where(id: ^deployment_group.id)
      |> Repo.update_all(set: [is_active: true, firmware_id: new_firmware.id])

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> click_button("Skip the queue")

      %{version: version, architecture: architecture, platform: platform} = new_firmware

      assert_receive %Broadcast{
        payload: %{
          firmware_url: firmware_url,
          firmware_meta: %{
            version: ^version,
            architecture: ^architecture,
            platform: ^platform
          }
        },
        event: "update"
      }

      assert String.starts_with?(firmware_url, "https://files.customer.com/download?")

      assert Repo.reload(device) |> Map.get(:updates_enabled)
    end

    test "allows a device to be sent the available delta update immediately, if a delta is available", %{
      conn: conn,
      org: org,
      org_key: org_key,
      product: product,
      device: device,
      deployment_group: deployment_group,
      tmp_dir: tmp_dir
    } do
      assert device.updates_enabled

      metadata = Map.put(device.firmware_metadata, :fwup_version, "1.13.0") |> Map.from_struct()
      Devices.update_device(device, %{firmware_metadata: metadata})

      device = Devices.update_deployment_group(device, deployment_group)
      {:ok, connection} = Connections.device_connecting(device, device.product_id)
      :ok = Connections.device_connected(device, connection.id)
      device = Devices.set_as_provisioned!(device)

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      Firmware
      |> where(id: ^new_firmware.id)
      |> Repo.update_all(set: [delta_updatable: true, version: "2.0.0"])

      {:ok, firmware} = Firmwares.get_firmware_by_product_id_and_uuid(device.product_id, device.firmware_metadata.uuid)
      _ = Fixtures.firmware_delta_fixture(firmware, new_firmware)

      DeploymentGroup
      |> where(id: ^deployment_group.id)
      |> Repo.update_all(set: [is_active: true, firmware_id: new_firmware.id, delta_updatable: true])

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> click_button("Skip the queue")

      %{architecture: architecture, platform: platform} = new_firmware

      assert_receive %Broadcast{
        payload: %{
          firmware_url: firmware_url,
          firmware_meta: %{
            version: "2.0.0",
            architecture: ^architecture,
            platform: ^platform
          }
        },
        event: "update"
      }

      assert String.ends_with?(firmware_url, ".delta.fw")

      assert Repo.reload(device) |> Map.get(:updates_enabled)
    end
  end

  describe "sending a manual full update" do
    test "lists only eligible firmwares for device", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user,
      fixture: %{firmware: firmware},
      tmp_dir: tmp_dir
    } do
      mismatched_architecture_firmware =
        Fixtures.org_key_fixture(org, user, tmp_dir)
        |> Fixtures.firmware_fixture(product, %{architecture: "arm", version: "1.5.0", dir: tmp_dir})

      mismatched_platform_firmware =
        Fixtures.org_key_fixture(org, user, tmp_dir)
        |> Fixtures.firmware_fixture(product, %{platform: "Vulture", version: "1.6.0", dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("option", text: firmware.version, exact_option: false)
      |> refute_has("option", text: mismatched_architecture_firmware.version, exact_option: false)
      |> refute_has("option", text: mismatched_platform_firmware.version, exact_option: false)
    end

    test "cannot send when device is disconnected", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      device = %{id: device_id} = Repo.preload(device, :latest_connection)
      refute device.latest_connection

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("button[disabled]", text: "Send full update")

      %{id: latest_connection_id} =
        DeviceConnection.create_changeset(%{
          product_id: product.id,
          device_id: device_id,
          established_at: DateTime.utc_now(),
          last_seen_at: DateTime.utc_now(),
          status: :connected
        })
        |> DeviceConnection.update_changeset(%{
          disconnected_at: DateTime.utc_now(),
          status: :disconnected
        })
        |> Repo.insert!()

      Device
      |> where(id: ^device_id)
      |> Repo.update_all(set: [latest_connection_id: latest_connection_id])

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("button[disabled]", text: "Send full update")
    end

    test "broadcasts the firmware update request, using the default url config", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      fixture: %{firmware: firmware}
    } do
      assert device.updates_enabled

      %{id: latest_connection_id} =
        DeviceConnection.create_changeset(%{
          product_id: device.product_id,
          device_id: device.id,
          established_at: DateTime.utc_now(),
          last_seen_at: DateTime.utc_now(),
          status: :connected
        })
        |> Repo.insert!()

      Device
      |> where(id: ^device.id)
      |> Repo.update_all(set: [latest_connection_id: latest_connection_id])

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> select("Firmware", option: firmware.version, exact_option: false)
      |> click_button("Send full update")

      %{version: version, architecture: architecture, platform: platform} = firmware

      assert_receive %Broadcast{
        payload: %{
          firmware_url: firmware_url,
          firmware_meta: %{
            version: ^version,
            architecture: ^architecture,
            platform: ^platform
          }
        },
        event: "update"
      }

      assert String.starts_with?(firmware_url, "http://localhost:1234")

      refute Repo.reload(device) |> Map.get(:updates_enabled)
    end

    test "broadcasts the firmware update request, and includes the Orgs `firmware_proxy_url` setting", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      fixture: %{firmware: firmware}
    } do
      Org
      |> where(id: ^org.id)
      |> Repo.update_all(set: [settings: %Org.Settings{firmware_proxy_url: "https://files.customer.com/download"}])

      assert device.updates_enabled

      %{id: latest_connection_id} =
        DeviceConnection.create_changeset(%{
          product_id: device.product_id,
          device_id: device.id,
          established_at: DateTime.utc_now(),
          last_seen_at: DateTime.utc_now(),
          status: :connected
        })
        |> Repo.insert!()

      Device
      |> where(id: ^device.id)
      |> Repo.update_all(set: [latest_connection_id: latest_connection_id])

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> select("Firmware", option: firmware.version, exact_option: false)
      |> click_button("Send full update")

      %{version: version, architecture: architecture, platform: platform} = firmware

      assert_receive %Broadcast{
        payload: %{
          firmware_url: firmware_url,
          firmware_meta: %{
            version: ^version,
            architecture: ^architecture,
            platform: ^platform
          }
        },
        event: "update"
      }

      assert String.starts_with?(firmware_url, "https://files.customer.com/download?firmware=")

      refute Repo.reload(device) |> Map.get(:updates_enabled)
    end

    test "broadcasts the firmware update request using the 'send delta' option", %{
      conn: conn,
      org: org,
      org_key: org_key,
      product: product,
      device: device,
      tmp_dir: tmp_dir
    } do
      assert device.updates_enabled

      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

      firmware_metadata = Map.put(device.firmware_metadata, :fwup_version, "1.13.0")

      %{id: latest_connection_id} =
        DeviceConnection.create_changeset(%{
          product_id: device.product_id,
          device_id: device.id,
          established_at: DateTime.utc_now(),
          last_seen_at: DateTime.utc_now(),
          status: :connected
        })
        |> Repo.insert!()

      Device
      |> where(id: ^device.id)
      |> Repo.update_all(set: [firmware_metadata: firmware_metadata, latest_connection_id: latest_connection_id])

      device = Repo.reload(device)

      Firmware
      |> where(id: ^new_firmware.id)
      |> Repo.update_all(set: [delta_updatable: true, version: "2.0.0"])

      new_firmware = Repo.reload(new_firmware)

      {:ok, firmware} = Firmwares.get_firmware_by_product_id_and_uuid(device.product_id, device.firmware_metadata.uuid)
      _ = Fixtures.firmware_delta_fixture(firmware, new_firmware)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> select("Firmware", option: new_firmware.version, exact_option: false)
      |> click_button("Send delta update")

      %{version: version, architecture: architecture, platform: platform} = new_firmware

      assert_receive %Broadcast{
        payload: %{
          firmware_url: firmware_url,
          firmware_meta: %{
            version: ^version,
            architecture: ^architecture,
            platform: ^platform
          }
        },
        event: "update"
      }

      assert String.ends_with?(firmware_url, ".delta.fw")

      refute Repo.reload(device) |> Map.get(:updates_enabled)
    end
  end

  describe "firmware validation and revert detection" do
    test "does not show the firmware box in the header if the firmware isn't reverted, or validated, or not validated",
         %{
           conn: conn,
           org: org,
           product: product,
           device: device
         } do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> refute_has("span", text: "Firmware:")
    end

    test "shows if a firmware revert is detected", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      Device
      |> where(id: ^device.id)
      |> Repo.update_all(set: [firmware_auto_revert_detected: true])

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("span", text: "Revert detected")
    end

    test "shows if the firmware has been validated", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      Device
      |> where(id: ^device.id)
      |> Repo.update_all(set: [firmware_validation_status: :validated])

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("span", text: "Validated")
    end

    test "shows if the firmware has not been validated", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      Device
      |> where(id: ^device.id)
      |> Repo.update_all(set: [firmware_validation_status: :not_validated])

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("span", text: "Not validated")
    end

    test "does not show if the firmware validation is unknown", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      Device
      |> where(id: ^device.id)
      |> Repo.update_all(set: [firmware_validation_status: :unknown])

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> refute_has("span", text: "Firmware:")
    end

    test "updates the firmware validation box when a firmware validation message is received", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      Device
      |> where(id: ^device.id)
      |> Repo.update_all(set: [firmware_validation_status: :not_validated])

      conn =
        conn
        |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
        |> assert_has("span", text: "Not validated")

      Devices.firmware_validated(device)

      assert_has(conn, "span", text: "Validated")
    end
  end

  def device_show_path(%{device: device, org: org, product: product}) do
    ~p"/org/#{org}/#{product}/devices/#{device}"
  end
end
