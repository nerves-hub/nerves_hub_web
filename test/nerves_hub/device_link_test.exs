defmodule NervesHub.DeviceLinkTest do
  use NervesHub.DataCase, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias NervesHub.AuditLogs.AuditLog
  alias NervesHub.Consoles
  alias NervesHub.DeviceLink
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.DeviceLink.Session
  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.FirmwareUpdates
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.ProductNotifications
  alias NervesHub.Products.Notification
  alias NervesHub.Repo
  alias Phoenix.Socket.Broadcast

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{is_active: true, user: user})
    device = Fixtures.device_fixture(org, product, firmware)

    {:ok,
     %{
       user: user,
       org: org,
       product: product,
       org_key: org_key,
       firmware: firmware,
       deployment_group: deployment_group,
       device: device
     }}
  end

  describe "status_update/2" do
    test "creates an InflightUpdate if none exists", %{device: device} do
      # Verify no InflightUpdates exists
      refute Repo.exists?(where(InflightUpdate, device_id: ^device.id))

      :ok = DeviceLink.status_update(to_device_info(device), %{"status" => "started"})

      # Verify the inflight update was created
      assert Repo.exists?(where(InflightUpdate, device_id: ^device.id))
    end

    test "manually requested firmware update is ignored by the device", %{device: device, firmware: firmware} do
      # Create an inflight update
      {:ok, _inflight_update} = Fixtures.inflight_update(device, firmware)

      # Verify a InflightUpdate is created
      assert Repo.exists?(where(InflightUpdate, device_id: ^device.id))

      :ok = DeviceLink.status_update(to_device_info(device), %{"status" => "ignored"})

      device = Repo.reload!(device)

      assert is_nil(device.updates_blocked_until)

      [_, audit_log] = Repo.all(AuditLog)
      assert audit_log.description =~ "ignored the manual firmware upgrade request"

      # Verify the inflight update is cleared
      refute Repo.exists?(where(InflightUpdate, device_id: ^device.id))
    end

    test "deployment scheduled firmware update is ignored by the device", %{
      device: device,
      deployment_group: deployment_group
    } do
      # Create an inflight update
      {:ok, _inflight_update} = Fixtures.inflight_update(device, deployment_group)

      # Verify a InflightUpdate is created
      assert Repo.exists?(where(InflightUpdate, device_id: ^device.id))

      :ok = DeviceLink.status_update(to_device_info(device), %{"status" => "ignored"})

      device = Repo.reload!(device)

      refute is_nil(device.updates_blocked_until)

      [_, audit_log] = Repo.all(AuditLog)
      assert audit_log.description =~ "ignored the scheduled firmware upgrade request"

      # Verify the inflight update is cleared
      refute Repo.exists?(where(InflightUpdate, device_id: ^device.id))
    end

    test "the device requests that the deployment scheduled firmware update is rescheduled", %{
      device: device,
      deployment_group: deployment_group
    } do
      # Create an inflight update
      {:ok, _inflight_update} = Fixtures.inflight_update(device, deployment_group)

      # Verify a InflightUpdate is created
      assert Repo.exists?(where(InflightUpdate, device_id: ^device.id))

      :ok =
        DeviceLink.status_update(to_device_info(device), %{
          "status" => "rescheduled",
          "delay_for" => to_timeout(minute: 15)
        })

      device = Repo.reload!(device)

      refute is_nil(device.updates_blocked_until)

      [_, audit_log] = Repo.all(AuditLog)
      assert audit_log.description =~ "requested firmware upgrades be rescheduled"

      # Verify the inflight update is cleared
      refute Repo.exists?(where(InflightUpdate, device_id: ^device.id))
    end

    test "the device requests that the manual requested firmware update is rescheduled", %{
      device: device,
      firmware: firmware
    } do
      # Create an inflight update
      {:ok, _inflight_update} = Fixtures.inflight_update(device, firmware)

      # Verify a InflightUpdate is created
      assert Repo.exists?(where(InflightUpdate, device_id: ^device.id))

      :ok =
        DeviceLink.status_update(to_device_info(device), %{
          "status" => "rescheduled",
          "delay_for" => to_timeout(minute: 15)
        })

      device = Repo.reload!(device)

      assert is_nil(device.updates_blocked_until)

      [_, audit_log] = Repo.all(AuditLog)
      assert audit_log.description =~ "requested firmware upgrades be rescheduled"
      assert audit_log.description =~ "The update will not be automatically retried"

      # Verify the inflight update is cleared
      refute Repo.exists?(where(InflightUpdate, device_id: ^device.id))
    end

    test "a firmware update scheduled by a deployment fails", %{
      device: device,
      deployment_group: deployment_group
    } do
      # Create an inflight update
      {:ok, _inflight_update} = Fixtures.inflight_update(device, deployment_group)

      # Verify a InflightUpdate is created
      assert Repo.exists?(where(InflightUpdate, device_id: ^device.id))

      :ok = DeviceLink.status_update(to_device_info(device), %{"status" => "failed"})

      device = Repo.reload!(device)

      refute is_nil(device.updates_blocked_until)

      [_, audit_log] = Repo.all(AuditLog)
      assert audit_log.description =~ "reported an error while trying to update its firmware"

      # Verify the inflight update is cleared
      refute Repo.exists?(where(InflightUpdate, device_id: ^device.id))
    end

    test "a manually requested firmware update fails", %{
      device: device,
      firmware: firmware
    } do
      # Create an inflight update
      {:ok, _inflight_update} = Fixtures.inflight_update(device, firmware)

      # Verify a InflightUpdate is created
      assert Repo.exists?(where(InflightUpdate, device_id: ^device.id))

      :ok = DeviceLink.status_update(to_device_info(device), %{"status" => "failed"})

      device = Repo.reload!(device)

      assert is_nil(device.updates_blocked_until)

      [_, audit_log] = Repo.all(AuditLog)
      assert audit_log.description =~ "reported an error while trying to update its firmware"

      # Verify the inflight update is cleared
      refute Repo.exists?(where(InflightUpdate, device_id: ^device.id))
    end

    test "downloading progress is only updated at most after 15 seconds", %{
      device: device,
      firmware: firmware
    } do
      # Create an inflight update
      {:ok, inflight_update} = Fixtures.inflight_update(device, firmware)

      # Verify a InflightUpdate is created
      assert Repo.exists?(where(InflightUpdate, device_id: ^device.id))

      :ok = DeviceLink.status_update(to_device_info(device), %{"status" => "downloading", "progress" => 15})

      inflight_update = Repo.reload!(inflight_update)
      assert inflight_update.progress == 15

      :ok = DeviceLink.status_update(to_device_info(device), %{"status" => "downloading", "progress" => 30})
      inflight_update = Repo.reload!(inflight_update)
      refute inflight_update.progress == 30

      # update to some reasonable time before 15s
      {1, _} =
        Repo.update_all(InflightUpdate, set: [updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(-10, :second)])

      :ok = DeviceLink.status_update(to_device_info(device), %{"status" => "downloading", "progress" => 30})
      inflight_update = Repo.reload!(inflight_update)
      refute inflight_update.progress == 30

      # update to some reasonable time after 15s
      {1, _} =
        Repo.update_all(InflightUpdate, set: [updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(-20, :second)])

      :ok = DeviceLink.status_update(to_device_info(device), %{"status" => "downloading", "progress" => 30})
      inflight_update = Repo.reload!(inflight_update)
      assert inflight_update.progress == 30
    end

    test "updating progress is only updated at most after 15 seconds", %{
      device: device,
      firmware: firmware
    } do
      # Create an inflight update
      {:ok, inflight_update} = Fixtures.inflight_update(device, firmware)

      # Verify a InflightUpdate is created
      assert Repo.exists?(where(InflightUpdate, device_id: ^device.id))

      :ok = DeviceLink.status_update(to_device_info(device), %{"status" => "updating", "progress" => 15})

      inflight_update = Repo.reload!(inflight_update)
      assert inflight_update.progress == 15

      :ok = DeviceLink.status_update(to_device_info(device), %{"status" => "updating", "progress" => 30})
      inflight_update = Repo.reload!(inflight_update)
      refute inflight_update.progress == 30

      # update to some reasonable time before 15s
      {1, _} =
        Repo.update_all(InflightUpdate, set: [updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(-10, :second)])

      :ok = DeviceLink.status_update(to_device_info(device), %{"status" => "updating", "progress" => 30})
      inflight_update = Repo.reload!(inflight_update)
      refute inflight_update.progress == 30

      # update to some reasonable time after 15s
      {1, _} =
        Repo.update_all(InflightUpdate, set: [updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(-20, :second)])

      :ok = DeviceLink.status_update(to_device_info(device), %{"status" => "updating", "progress" => 30})
      inflight_update = Repo.reload!(inflight_update)
      assert inflight_update.progress == 30
    end

    test "the firmware update completes successfully", %{
      device: device,
      firmware: firmware
    } do
      # Create an inflight update
      {:ok, _inflight_update} = Fixtures.inflight_update(device, firmware)

      # Verify a InflightUpdate is created
      assert Repo.exists?(where(InflightUpdate, device_id: ^device.id))

      :ok = DeviceLink.status_update(to_device_info(device), %{"status" => "completed"})

      device = Repo.reload!(device)

      assert is_nil(device.updates_blocked_until)

      # Verify the inflight update is not cleared
      assert Repo.exists?(where(InflightUpdate, device_id: ^device.id))
    end

    test "clears a device's InflightUpdate when status contains \"encountered fwup error\"", %{
      device: device,
      deployment_group: deployment_group
    } do
      # Create an inflight update
      {:ok, _inflight_update} = Fixtures.inflight_update(device, deployment_group)

      # Verify the inflight update exists
      assert Repo.exists?(where(InflightUpdate, device_id: ^device.id))

      # Call status_update with a status containing "encountered fwup error"
      :ok = DeviceLink.status_update(to_device_info(device), %{"status" => "Update failed: encountered fwup error"})

      # Verify the inflight update was cleared
      refute Repo.exists?(where(InflightUpdate, device_id: ^device.id))
    end

    test "clears a device's InflightUpdate when status contains \"fwup error\"", %{
      device: device,
      deployment_group: deployment_group
    } do
      # Create an inflight update
      {:ok, _inflight_update} = Fixtures.inflight_update(device, deployment_group)

      # Verify the inflight update exists
      assert Repo.exists?(where(InflightUpdate, device_id: ^device.id))

      # Call status_update with a status containing "FWUP error: failure of some sort"
      :ok = DeviceLink.status_update(to_device_info(device), %{"status" => "FWUP error: failure of some sort"})

      # Verify the inflight update was cleared
      refute Repo.exists?(where(InflightUpdate, device_id: ^device.id))
    end

    test "does not clear a devices InflightUpdate when status does not contain \"fwup error\"", %{
      device: device,
      deployment_group: deployment_group
    } do
      # Create an inflight update
      {:ok, _inflight_update} = Fixtures.inflight_update(device, deployment_group)

      # Verify the inflight update exists
      assert Repo.exists?(where(InflightUpdate, device_id: ^device.id))

      # Call status_update with a status that does not contain "fwup error"
      :ok = DeviceLink.status_update(to_device_info(device), %{"status" => "updating"})

      # Verify the inflight update still exists
      assert Repo.exists?(where(InflightUpdate, device_id: ^device.id))
    end

    test "'started' messages from device execute telemetry when there's a network interface mismatch", %{
      device: device,
      firmware: firmware
    } do
      # Create an inflight update
      {:ok, _inflight_update} = Fixtures.inflight_update(device, firmware)

      assert {:ok, %DeviceConnection{id: ref, status: :connecting} = connection} =
               Connections.device_connecting(device.org_id, device.product_id, device.id)

      refute connection.network_interface

      {:ok, _connection} = Connections.update_network_interface(ref, "eth0")

      expect(:telemetry, :execute, fn _event, _measurements, metadata ->
        assert metadata.downloader_network_interface == "eth0"
        assert metadata.device_network_interface == :wifi
      end)

      device_info = Repo.reload(device) |> to_device_info()

      :ok =
        DeviceLink.status_update(device_info, %{"status" => "started", "downloader_network_interface" => "eth0"})
    end

    test "'started' messages from device do not blow up if downloader network interface is nil", %{
      device: device,
      firmware: firmware
    } do
      # Create an inflight update
      {:ok, _inflight_update} = Fixtures.inflight_update(device, firmware)

      expect(:telemetry, :execute, fn _event, _measurements, metadata ->
        assert metadata.identifier == device.identifier
      end)

      :ok =
        DeviceLink.status_update(to_device_info(device), %{"status" => "started", "downloader_network_interface" => nil})
    end
  end

  describe "connect/3" do
    test "records the client library the User-Agent names", %{device: device} do
      device_info = %{to_device_info(device) | org_id: device.org_id}

      assert {:ok, %DeviceInfo{connection_ref: ref}} =
               DeviceLink.connect(device_info, "203.0.113.7", "NHL/2.13.0 Mint/1.7.1")

      assert %DeviceConnection{id: ^ref, ip_address: "203.0.113.7", lib: "nerves_hub_link", lib_version: "2.13.0"} =
               Connections.get_latest_for_device(device.id)
    end

    # What a node holding sockets calls while it is still on a release that
    # doesn't forward the header.
    test "records an unknown client library when called without one", %{device: device} do
      device_info = %{to_device_info(device) | org_id: device.org_id}

      assert {:ok, %DeviceInfo{connection_ref: ref}} = DeviceLink.connect(device_info, "203.0.113.7")

      assert %DeviceConnection{id: ^ref, lib: nil, lib_version: nil} = Connections.get_latest_for_device(device.id)
    end

    # A device that collided with a soft-deleted one, and connected once that
    # was restored or removed.
    test "clears the notification that its identifier was in use", %{device: device, product: product} do
      device_info = %{to_device_info(device) | org_id: device.org_id}

      _ =
        ProductNotifications.create_duplicate_device_identifier_notification!(
          product.id,
          device.identifier,
          :shared_secrets
        )

      other =
        ProductNotifications.create_duplicate_device_identifier_notification!(product.id, "other", :shared_secrets)

      assert {:ok, %DeviceInfo{}} = DeviceLink.connect(device_info, "203.0.113.7")

      assert [%Notification{id: other_id}] = Repo.all(Notification)
      assert other_id == other.id
    end
  end

  describe "join/2" do
    test "keeps the old firmware on record when the update that installed the new one cannot be recorded", %{
      device: device,
      org_key: org_key,
      product: product,
      tmp_dir: tmp_dir
    } do
      previous_uuid = device.firmware_metadata.uuid
      new_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      {:ok, _inflight_update} = Fixtures.inflight_update(device, new_firmware)

      stub(FirmwareUpdates, :firmware_update_successful, fn _device, _previous_metadata ->
        {:error, :unavailable}
      end)

      params = %{"nerves_fw_uuid" => new_firmware.uuid, "device_api_version" => "2.2.0"}

      assert {:error, {:error, :unavailable}} = DeviceLink.join(connected_device_info(device), params)

      # Had the new firmware been kept, the next join would see nothing new and
      # end this update as abandoned rather than finish it.
      assert Repo.reload!(device).firmware_metadata.uuid == previous_uuid
      assert Repo.get_by(InflightUpdate, device_id: device.id)
    end
  end

  describe "device_message/3 sleeping and rebooting" do
    setup %{device: device} do
      device_info = connected_device_info(device)
      :ok = Connections.device_connected(device_info.connection_ref)

      {:ok, %{session: %Session{device_info: device_info}}}
    end

    test "sleeping records deep sleep and when the device will be back", %{device: device, session: session} do
      before = DateTime.utc_now()

      assert {_session, []} =
               DeviceLink.device_message(session, "sleeping", %{"mode" => "deep", "duration_ms" => 300_000})

      connection = Connections.get_latest_for_device(device.id)
      assert connection.disconnected_reason == :deep_sleep
      assert connection.status == :connected

      assert DateTime.diff(connection.expected_wake_at, before, :second) in 299..301
    end

    test "sleeping in light mode records light sleep", %{device: device, session: session} do
      DeviceLink.device_message(session, "sleeping", %{"mode" => "light", "duration_ms" => 1_000})

      assert Connections.get_latest_for_device(device.id).disconnected_reason == :light_sleep
    end

    # A device waiting on a GPIO or the ULP has no time to give.
    test "sleeping with no duration records no wake time", %{device: device, session: session} do
      DeviceLink.device_message(session, "sleeping", %{"mode" => "deep"})

      assert %DeviceConnection{disconnected_reason: :deep_sleep, expected_wake_at: nil} =
               Connections.get_latest_for_device(device.id)
    end

    test "a duration that is not a sensible number of milliseconds is ignored", %{device: device, session: session} do
      for duration <- [-5, 0, "300000", 1.5, to_timeout(day: 400)] do
        DeviceLink.device_message(session, "sleeping", %{"duration_ms" => duration})

        assert %DeviceConnection{disconnected_reason: :deep_sleep, expected_wake_at: nil} =
                 Connections.get_latest_for_device(device.id)
      end
    end

    test "sleeping with no payload at all is taken as deep sleep", %{device: device, session: session} do
      assert {_session, []} = DeviceLink.device_message(session, "sleeping", nil)

      assert Connections.get_latest_for_device(device.id).disconnected_reason == :deep_sleep
    end

    test "rebooting records the reason", %{device: device, session: session} do
      assert {_session, []} = DeviceLink.device_message(session, "rebooting", %{})

      assert Connections.get_latest_for_device(device.id).disconnected_reason == :rebooting
    end
  end

  describe "device_message/3 report_device_metadata" do
    setup %{device: device} do
      device_info = connected_device_info(device)

      {:ok, %{session: %Session{device_info: device_info}}}
    end

    test "merges the metadata into the connection", %{device: device, session: session} do
      assert {_session, []} =
               DeviceLink.device_message(session, "report_device_metadata", %{
                 "metadata" => %{"placement" => "the shed", "board_revision" => "c"}
               })

      assert %DeviceConnection{metadata: %{"placement" => "the shed", "board_revision" => "c"}} =
               Connections.get_latest_for_device(device.id)
    end

    test "a second message merges rather than replacing", %{device: device, session: session} do
      DeviceLink.device_message(session, "report_device_metadata", %{
        "metadata" => %{"placement" => "the shed", "board_revision" => "c"}
      })

      DeviceLink.device_message(session, "report_device_metadata", %{"metadata" => %{"placement" => "the barn"}})

      assert %DeviceConnection{metadata: %{"placement" => "the barn", "board_revision" => "c"}} =
               Connections.get_latest_for_device(device.id)
    end

    test "keeps what the platform put on the connection", %{device: device, session: session} do
      :ok =
        DeviceLink.update_connection_metadata(session.device_info.connection_ref, %{"device_api_version" => "2.3.0"})

      DeviceLink.device_message(session, "report_device_metadata", %{"metadata" => %{"placement" => "the shed"}})

      assert %DeviceConnection{metadata: %{"device_api_version" => "2.3.0", "placement" => "the shed"}} =
               Connections.get_latest_for_device(device.id)
    end

    test "an empty map leaves the connection alone", %{device: device, session: session} do
      DeviceLink.device_message(session, "report_device_metadata", %{"metadata" => %{"placement" => "the shed"}})

      assert {_session, []} = DeviceLink.device_message(session, "report_device_metadata", %{"metadata" => %{}})

      assert %DeviceConnection{metadata: %{"placement" => "the shed"}} = Connections.get_latest_for_device(device.id)
    end

    test "a malformed payload is ignored without taking the link down", %{device: device, session: session} do
      DeviceLink.device_message(session, "report_device_metadata", %{"metadata" => %{"placement" => "the shed"}})

      test_pid = self()
      handler_id = {__MODULE__, make_ref()}

      :ok =
        :telemetry.attach(
          handler_id,
          [:nerves_hub, :devices, :unhandled_in],
          fn _event, _measurements, metadata, _config -> send(test_pid, {:unhandled_in, metadata.msg}) end,
          nil
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      for payload <- [
            %{"metadata" => ["placement", "the barn"]},
            %{"metadata" => "the barn"},
            %{"metadata" => nil},
            %{"placement" => "the barn"},
            nil
          ] do
        assert {^session, []} = DeviceLink.device_message(session, "report_device_metadata", payload)
        assert_receive {:unhandled_in, "report_device_metadata"}
      end

      assert %DeviceConnection{metadata: %{"placement" => "the shed"}} = Connections.get_latest_for_device(device.id)
    end
  end

  describe "disconnect/2" do
    setup %{device: device} do
      device_info = connected_device_info(device)
      :ok = Connections.device_connected(device_info.connection_ref)

      {:ok, %{device_info: device_info}}
    end

    test "reads the reason the Client sends as a string", %{device: device, device_info: device_info} do
      assert :ok = DeviceLink.disconnect(device_info.connection_ref, "duplicate_connection")

      assert Connections.get_latest_for_device(device.id).disconnected_reason == :duplicate_connection
    end

    test "records a reason this release doesn't know as none", %{device: device, device_info: device_info} do
      assert :ok = DeviceLink.disconnect(device_info.connection_ref, "from_a_newer_release")

      assert %DeviceConnection{status: :disconnected, disconnected_reason: nil} =
               Connections.get_latest_for_device(device.id)
    end
  end

  describe "device_message/3 progress events" do
    setup %{device: device, firmware: firmware} do
      {:ok, inflight_update} = Fixtures.inflight_update(device, firmware)
      session = %Session{device_info: to_device_info(device)}

      {:ok, %{inflight_update: inflight_update, session: session}}
    end

    # Every deployed nerves_hub_link sends this name and cannot be changed.
    test "fwup_progress records progress", %{inflight_update: inflight_update, session: session} do
      assert {_session, []} =
               DeviceLink.device_message(session, "fwup_progress", %{"value" => 42, "stage" => "downloading"})

      inflight_update = Repo.reload!(inflight_update)
      assert inflight_update.progress == 42
      assert inflight_update.status == :downloading
    end

    # The tool-neutral name a non-Nerves agent should send.
    test "update_progress records progress identically", %{inflight_update: inflight_update, session: session} do
      assert {_session, []} =
               DeviceLink.device_message(session, "update_progress", %{"value" => 42, "stage" => "downloading"})

      inflight_update = Repo.reload!(inflight_update)
      assert inflight_update.progress == 42
      assert inflight_update.status == :downloading
    end

    test "update_progress without a stage is treated as updating", %{
      inflight_update: inflight_update,
      session: session
    } do
      assert {_session, []} = DeviceLink.device_message(session, "update_progress", %{"value" => 30})

      assert Repo.reload!(inflight_update).status == :updating
    end

    test "update_progress at 100 with no stage completes", %{inflight_update: inflight_update, session: session} do
      assert {_session, []} = DeviceLink.device_message(session, "update_progress", %{"value" => 100})

      assert Repo.reload!(inflight_update).status == :completed
    end

    # The catch-all clause must swallow a malformed message rather than crash
    # the link and take the device's connection with it.
    test "a progress message with no value is ignored", %{session: session} do
      assert {_session, []} = DeviceLink.device_message(session, "update_progress", %{})
    end
  end

  describe "device_notify/2 :after_join connecting code" do
    test "echoes the connecting code to the console for devices too old to run scripts", %{
      device: device
    } do
      {:ok, device} = Devices.update_device(device, %{connecting_code: ~s/dbg("boo")/})

      # Stand in for the device-side console channel, which is what carries the
      # echo down to the device.
      :ok = Consoles.PubSub.subscribe_console(device.id)

      session = %Session{device_info: connected_device_info(device), device_api_version: "2.0.0"}
      params = %{"device_api_version" => "2.0.0"}

      {_session, effects} = DeviceLink.device_notify(session, {:after_join, params})

      assert effects == []
      assert_receive %Broadcast{event: "dn", payload: %{"data" => ~s/dbg("boo")\n\r/}}, 500
    end

    test "pushes a script instead of echoing when the device can run scripts", %{device: device} do
      {:ok, device} = Devices.update_device(device, %{connecting_code: ~s/dbg("boo")/})

      :ok = Consoles.PubSub.subscribe_console(device.id)

      session = %Session{device_info: connected_device_info(device), device_api_version: "2.1.0"}
      params = %{"device_api_version" => "2.1.0"}

      {_session, effects} = DeviceLink.device_notify(session, {:after_join, params})

      assert [{:push, "scripts/run", %{"text" => ~s/dbg("boo")/}}] = effects
      refute_receive %Broadcast{event: "dn"}, 200
    end
  end

  describe "device_message/3 answering the connecting code" do
    setup %{device: device} do
      {:ok, device} = Devices.update_device(device, %{connecting_code: ~s/raise "boom"/})

      test_pid = self()
      handler_id = {__MODULE__, make_ref()}

      :ok =
        :telemetry.attach_many(
          handler_id,
          [
            [:nerves_hub, :devices, :connecting_code_failure],
            [:nerves_hub, :devices, :connecting_code_success]
          ],
          fn event, _measurements, metadata, _config -> send(test_pid, {:telemetry, event, metadata}) end,
          nil
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      %{device: device, session: %Session{device_info: to_device_info(device), device_api_version: "2.1.0"}}
    end

    test "a script nerves_hub_link could not run raises a notification", %{device: device, session: session} do
      payload = %{
        "ref" => "connecting_code",
        "result" => "error",
        "reason" => "timeout",
        "output" => "Error running script: timeout exceeded",
        "return" => ""
      }

      assert {_session, []} = DeviceLink.device_message(session, "scripts/run", payload)

      identifier = device.identifier

      assert_receive {:telemetry, [:nerves_hub, :devices, :connecting_code_failure],
                      %{identifier: ^identifier, output: "Error running script: timeout exceeded"}}

      assert [notification] = Repo.all(Notification)
      assert notification.product_id == device.product_id
      assert notification.metadata["reason"] == "Error running script: timeout exceeded"
    end

    test "a non-zero exit from the Linux agent raises a notification with the status", %{session: session} do
      payload = %{
        "ref" => "connecting_code",
        "result" => "error",
        "return" => "exited with status 127",
        "output" => "sh: frobnicate: not found\n"
      }

      _ = DeviceLink.device_message(session, "scripts/run", payload)

      assert [notification] = Repo.all(Notification)
      assert notification.metadata["reason"] == "exited with status 127: sh: frobnicate: not found"
    end

    # nerves_hub_link catches the exception and reports the run as completed.
    test "code that raised is a failure, reported by its exception", %{session: session} do
      payload = %{
        "ref" => "connecting_code",
        "result" => "completed",
        "return" => "nil",
        "output" => "starting\n\n** (RuntimeError) boom"
      }

      _ = DeviceLink.device_message(session, "scripts/run", payload)

      assert_receive {:telemetry, [:nerves_hub, :devices, :connecting_code_failure], _}
      assert [notification] = Repo.all(Notification)
      assert notification.metadata["reason"] == "** (RuntimeError) boom"
    end

    # Releases from before `"result"` existed send the same answer without it.
    test "code that raised on an older nerves_hub_link is a failure", %{session: session} do
      payload = %{"ref" => "connecting_code", "return" => "nil", "output" => "\n** (RuntimeError) boom"}

      _ = DeviceLink.device_message(session, "scripts/run", payload)

      assert_receive {:telemetry, [:nerves_hub, :devices, :connecting_code_failure], _}
      assert [notification] = Repo.all(Notification)
      assert notification.metadata["reason"] == "** (RuntimeError) boom"
    end

    test "a notification that cannot be written does not raise", %{session: session} do
      stub(ProductNotifications, :create_connecting_code_failure_notification!, fn _device_info, _code, _reason ->
        raise DBConnection.ConnectionError, "connection not available"
      end)

      payload = %{"ref" => "connecting_code", "result" => "error", "return" => "", "output" => "boom"}

      log =
        capture_log(fn ->
          assert {_session, []} = DeviceLink.device_message(session, "scripts/run", payload)
        end)

      assert log =~ "Could not record the connecting code failure"
      assert log =~ "connection not available"
    end

    test "code that returned nil without raising succeeded", %{session: session} do
      payload = %{"ref" => "connecting_code", "result" => "completed", "return" => "nil", "output" => "hello\n"}

      _ = DeviceLink.device_message(session, "scripts/run", payload)

      assert_receive {:telemetry, [:nerves_hub, :devices, :connecting_code_success], _}
      assert Repo.all(Notification) == []
    end

    test "code that has been removed since it was sent raises no notification", %{device: device, session: session} do
      {:ok, _device} = Devices.update_device(device, %{connecting_code: nil})

      payload = %{"ref" => "connecting_code", "result" => "error", "return" => "", "output" => "boom"}
      _ = DeviceLink.device_message(session, "scripts/run", payload)

      assert_receive {:telemetry, [:nerves_hub, :devices, :connecting_code_failure], _}
      assert Repo.all(Notification) == []
    end

    test "devices failing on their deployment group's code share one notification", %{
      user: user,
      org: org,
      product: product,
      firmware: firmware,
      deployment_group: deployment_group
    } do
      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{connecting_code: ~s/raise "group"/}, user)

      payload = %{"ref" => "connecting_code", "result" => "error", "return" => "", "output" => "boom"}

      for _ <- 1..2 do
        device = Fixtures.device_fixture(org, product, firmware, %{deployment_id: deployment_group.id})
        session = %Session{device_info: to_device_info(device), device_api_version: "2.1.0"}

        _ = DeviceLink.device_message(session, "scripts/run", payload)
      end

      assert [notification] = Repo.all(Notification)
      assert notification.occurrence_count == 2
    end
  end

  # `after_join/2` reaches for the org, the allowed extension list and a live
  # connection, none of which the minimal `to_device_info/1` above populates.
  defp connected_device_info(device) do
    {:ok, connection} = Connections.device_connecting(device.org_id, device.product_id, device.id)

    %{
      to_device_info(device)
      | org_id: device.org_id,
        allowed_extensions: [],
        connection_ref: connection.id
    }
  end

  def to_device_info(device) do
    %DeviceInfo{device_id: device.id, device_identifier: device.identifier, product_id: device.product_id}
  end
end
