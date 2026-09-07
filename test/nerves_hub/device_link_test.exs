defmodule NervesHub.DeviceLinkTest do
  use NervesHub.DataCase, async: true
  use Mimic

  alias NervesHub.AuditLogs.AuditLog
  alias NervesHub.Consoles
  alias NervesHub.DeviceLink
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.DeviceLink.Session
  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Fixtures
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

      {1, _} =
        Repo.update_all(InflightUpdate, set: [updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(-14, :second)])

      :ok = DeviceLink.status_update(to_device_info(device), %{"status" => "downloading", "progress" => 30})
      inflight_update = Repo.reload!(inflight_update)
      refute inflight_update.progress == 30

      {1, _} =
        Repo.update_all(InflightUpdate, set: [updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(-16, :second)])

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

      :ok = DeviceLink.status_update(to_device_info(device), %{"status" => "downloading", "progress" => 30})
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
      :ok = Consoles.PubSub.join_console(device.id)

      session = %Session{device_info: connected_device_info(device), device_api_version: "2.0.0"}
      params = %{"device_api_version" => "2.0.0"}

      {_session, effects} = DeviceLink.device_notify(session, {:after_join, params})

      assert effects == []
      assert_receive %Broadcast{event: "dn", payload: %{"data" => ~s/dbg("boo")\n\r/}}, 500
    end

    test "pushes a script instead of echoing when the device can run scripts", %{device: device} do
      {:ok, device} = Devices.update_device(device, %{connecting_code: ~s/dbg("boo")/})

      :ok = Consoles.PubSub.join_console(device.id)

      session = %Session{device_info: connected_device_info(device), device_api_version: "2.1.0"}
      params = %{"device_api_version" => "2.1.0"}

      {_session, effects} = DeviceLink.device_notify(session, {:after_join, params})

      assert [{:push, "scripts/run", %{"text" => ~s/dbg("boo")/}}] = effects
      refute_receive %Broadcast{event: "dn"}, 200
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
