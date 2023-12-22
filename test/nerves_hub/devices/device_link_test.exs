defmodule NervesHub.DeviceLinkTest do
  use NervesHub.DataCase
  use DefaultMocks

  alias NervesHub.AuditLogs
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceLink
  alias NervesHub.Fixtures
  alias NervesHub.Tracker
  alias Phoenix.Socket.Broadcast

  test "device without deployment subscribes deployment:none" do
    state = %DeviceLink.State{device: %Device{id: 1, deployment_id: nil}}
    assert {:noreply, updated} = DeviceLink.handle_continue(:boot, state)
    assert updated.deployment_channel == "deployment:none"
  end

  test "device with deployment subscribes deployment:\#{id}" do
    state = %DeviceLink.State{device: %Device{id: 1, deployment_id: 1}}
    assert {:noreply, updated} = DeviceLink.handle_continue(:boot, state)
    assert updated.deployment_channel == "deployment:1"
  end

  describe "connect/4" do
    setup [:create_device, :start_device_link]

    test "registers link process presence with the cluster", %{device: device, link: link} do
      push_cb = fn _, _ -> :ok end
      DeviceLink.connect(device, push_cb, %{})
      # Make sure the channel has performed it's after join
      _ = :sys.get_state(link)

      # Make sure the tracker is caught up as well
      _ = :sys.get_state(Tracker.DeviceShard.name(Tracker.shard(device)))

      assert Tracker.online?(device)

      expected_meta = %{
        firmware_uuid: device.firmware_metadata.uuid,
        updates_enabled: true,
        deployment_id: nil,
        updating: false
      }

      assert [{^link, ^expected_meta}] = Registry.lookup(Devices, device.id)
    end

    test "clears any previous inflight updates", context do
      assert Devices.count_inflight_updates_for(context.deployment) == 0
      assert {:ok, _} = Devices.told_to_update(context.device, context.deployment)
      assert Devices.count_inflight_updates_for(context.deployment) == 1

      push_cb = fn _, _ -> :ok end
      assert {:ok, _link} = DeviceLink.connect(context.device, push_cb, %{})
      assert Devices.count_inflight_updates_for(context.deployment) == 0
    end

    test "audits the connection", %{device: device, link: link} do
      assert [] = AuditLogs.logs_for(device)
      push_cb = fn _, _ -> :ok end
      assert {:ok, _link} = DeviceLink.connect(device, push_cb, %{})
      reference_id = :sys.get_state(link).reference_id
      assert log = Enum.find(AuditLogs.logs_for(device), &(reference_id == &1.reference_id))
      assert log.description == "device #{device.identifier} connected to the server"
    end

    test "pushes update if one is available", %{
      device: device,
      deployment: deployment,
      link: link
    } do
      assert {:ok, device} = Devices.update_device(device, %{deployment_id: deployment.id})
      assert device.updates_enabled

      params =
        for {k, v} <- Map.from_struct(device.firmware_metadata), into: %{} do
          case k do
            :uuid -> {"nerves_fw_uuid", Ecto.UUID.generate()}
            _ -> {"nerves_fw_#{k}", v}
          end
        end

      :sys.replace_state(link, &%{&1 | device: device})
      test_pid = self()
      push_cb = fn e, p -> send(test_pid, {:push, e, p}) end
      assert {:ok, _link} = DeviceLink.connect(link, push_cb, params)

      # Pushes the update payload to device via transport
      assert_receive {:push, "update", payload}
      assert payload.update_available
      assert payload.firmware_url

      # logs the update
      assert Enum.find(AuditLogs.logs_for(device), fn al ->
               al.description ==
                 "device #{device.identifier} received update for firmware #{deployment.firmware.version}(#{deployment.firmware.uuid}) via deployment #{deployment.name} on connect"
             end)

      # Confirms there is an update inflight
      assert Devices.count_inflight_updates_for(deployment) == 1
    end

    test "can monitor a transport process", context do
      state = :sys.get_state(context.link)
      refute is_nil(state.reference_id)
      push_cb = fn _, _ -> :ok end

      monitor_pid =
        spawn(fn ->
          assert {:ok, _link} = DeviceLink.connect(context.link, push_cb, %{}, monitor: "howdy")
          # We want this process alive to check it's closing shortly
          :timer.sleep(1000)
        end)

      :timer.sleep(50)
      updated = :sys.get_state(context.link)
      assert state.reference_id != updated.reference_id
      assert updated.reference_id == "howdy"
      assert updated.transport_pid == monitor_pid
      assert updated.transport_ref

      # If the monitor process closes, so does the link
      assert Process.exit(monitor_pid, :kill)
      refute Process.alive?(monitor_pid)

      # Timer for reconnect is started
      assert :sys.get_state(context.link).reconnect_timer

      # audits the disconnect
      assert al =
               Enum.find(AuditLogs.logs_for(context.device), fn al ->
                 al.description ==
                   "device #{context.device.identifier} disconnected from the server"
               end)

      assert al.reference_id == updated.reference_id
      refute Tracker.online?(context.device)
      assert [] = Registry.lookup(Devices, context.device.id)
    end

    test "calling disconnect/1 on a connected link adds audit log, removes presence, and starts reconnect timer",
         %{device: device, link: link} do
      push_cb = fn _, _ -> :ok end
      assert {:ok, ^link} = DeviceLink.connect(link, push_cb, %{})
      assert :ok = DeviceLink.disconnect(link)

      assert Enum.find(AuditLogs.logs_for(device), fn al ->
               al.description == "device #{device.identifier} disconnected from the server"
             end)

      refute Tracker.online?(device)
      assert [] = Registry.lookup(Devices, device.id)

      # Timer for reconnect is started
      assert :sys.get_state(link).reconnect_timer
    end
  end

  test "disconnect/1 adds audit log, removes presence, and starts reconnect timer", context do
    %{device: device, link: link} = create_device(context) |> start_device_link()
    assert :ok = DeviceLink.disconnect(link)

    assert Enum.find(AuditLogs.logs_for(device), fn al ->
             al.description == "device #{device.identifier} disconnected from the server"
           end)

    refute Tracker.online?(device)
    assert [] = Registry.lookup(Devices, device.id)

    # Timer for reconnect is started
    assert :sys.get_state(link).reconnect_timer
  end

  describe "recv/3 events" do
    setup [:create_device, :start_device_link]

    test "the first fwup_progress marks an update as happening", %{device: device, link: link} do
      Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device.identifier}:internal")

      assert :ok = DeviceLink.recv(link, "fwup_progress", %{"value" => 10})

      # Tell any internal watchers progress is happening
      assert_receive %{event: "fwup_progress", payload: %{percent: 10}}

      state = :sys.get_state(link)
      assert state.update_started?
      assert length(state.device.update_attempts) == length(device.update_attempts) + 1
      assert [{^link, %{updating: true}}] = Registry.lookup(Devices, device.id)
    end

    test "subsequent fwup_progress only broadcasts", %{device: device, link: link} do
      :sys.replace_state(link, &%{&1 | update_started?: true})
      Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device.identifier}:internal")
      assert :ok = DeviceLink.recv(link, "fwup_progress", %{"value" => 10})

      # Tell any internal watchers progress is happening
      assert_receive %{event: "fwup_progress", payload: %{percent: 10}}

      assert %{device: ^device} = :sys.get_state(link)
    end

    test "status_update is handled but makes no changes", %{device: device, link: link} do
      assert :ok = DeviceLink.recv(link, "status_update", %{"status" => "wat"})
      assert %{device: ^device} = :sys.get_state(link)
    end

    test "rebooting is handled but makes no changes", %{device: device, link: link} do
      assert :ok = DeviceLink.recv(link, "rebooting", %{})
      assert %{device: ^device} = :sys.get_state(link)
    end

    test "connection_types updates the device", %{device: device, link: link} do
      refute device.connection_types
      assert :ok = DeviceLink.recv(link, "connection_types", %{"values" => ["ethernet", "wifi"]})
      device = NervesHub.Repo.reload(device)
      assert device.connection_types == [:ethernet, :wifi]
    end

    test "unhandled events return error", %{link: link} do
      assert {:error, :unhandled} = DeviceLink.recv(link, "wat", %{})
    end
  end

  test "assigns matching deployment when changed and none set", context do
    %{device: device, deployment: deployment} = create_device(context)
    refute device.deployment_id

    channel = "deployment:none"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, channel)

    assert {:ok, deployment} =
             NervesHub.Deployments.update_deployment(deployment, %{is_active: true})

    assert_receive msg = %Broadcast{event: "deployments/changed", topic: channel}
    state = %DeviceLink.State{device: device, deployment_channel: channel}
    assert {:noreply, updated} = DeviceLink.handle_info(msg, state)

    assert updated.device.deployment_id == deployment.id
  end

  test "ignores non-matching deployment when none set", context do
    %{device: device, deployment: deployment} = create_device(Map.put(context, :tags, ["wat"]))
    refute device.deployment_id

    channel = "deployment:none"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, channel)

    assert {:ok, _deployment} =
             NervesHub.Deployments.update_deployment(deployment, %{is_active: true})

    assert_receive msg = %Broadcast{event: "deployments/changed", topic: channel}
    state = %DeviceLink.State{device: device, deployment_channel: channel}
    assert {:noreply, ^state} = DeviceLink.handle_info(msg, state)
  end

  test "matching deployment replaces existing deployment when changed", context do
    %{device: device, deployment: deployment} = create_device(context)
    refute device.deployment_id
    channel = "deployment:#{deployment.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, channel)

    assert {:ok, deployment} =
             NervesHub.Deployments.update_deployment(deployment, %{
               is_active: true,
               conditions: %{"tags" => device.tags, "version" => ""}
             })

    assert_receive msg = %Broadcast{event: "deployments/changed", topic: channel}

    state = %DeviceLink.State{
      device: %{device | deployment_id: deployment.id + 1},
      deployment_channel: channel
    }

    assert {:noreply, updated} = DeviceLink.handle_info(msg, state)

    assert updated.device.deployment_id == deployment.id
  end

  test "resolves changed deployment when it no longer matches", context do
    %{device: device, deployment: deployment} = create_device(context)
    refute device.deployment_id
    channel = "deployment:#{deployment.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, channel)

    assert {:ok, deployment} =
             NervesHub.Deployments.update_deployment(deployment, %{
               is_active: true,
               conditions: %{"tags" => ["wat"], "version" => ""}
             })

    assert_receive msg = %Broadcast{event: "deployments/changed", topic: channel}

    state = %DeviceLink.State{
      device: %{device | deployment_id: deployment.id},
      deployment_channel: channel
    }

    # Nothing changes and the resolution is scheduled
    assert {:noreply, ^state} = DeviceLink.handle_info(msg, state)
    assert state.device.deployment_id

    assert {:noreply, updated} = DeviceLink.handle_info(:resolve_changed_deployment, state)
    refute updated.device.deployment_id
    assert updated.deployment_channel == "deployment:none"

    assert Enum.find(AuditLogs.logs_for(device), fn al ->
             al.description ==
               "device #{device.identifier} reloaded deployment and is no longer attached to a deployment"
           end)
  end

  test "resolves changed deployment and assigns when matching", context do
    context = create_device(context)
    %{device: device, deployment: deployment} = context
    refute device.deployment_id

    channel = "deployment:#{deployment.id}"

    assert {:ok, deployment} =
             NervesHub.Deployments.update_deployment(deployment, %{
               is_active: true,
               conditions: %{"tags" => device.tags, "version" => ""}
             })

    state = %DeviceLink.State{device: device, deployment_channel: channel}

    assert {:noreply, updated} = DeviceLink.handle_info(:resolve_changed_deployment, state)
    assert updated.device.deployment_id == deployment.id
    assert updated.deployment_channel == channel

    assert Enum.find(AuditLogs.logs_for(device), fn al ->
             al.description ==
               "device #{device.identifier} reloaded deployment and is attached to deployment #{deployment.name}"
           end)
  end

  test "pushes manual updates" do
    test_pid = self()
    push_cb = fn e, p -> send(test_pid, {:push, e, p}) end
    state = %DeviceLink.State{device: %Device{id: 1}, push_cb: push_cb}
    payload = %{deployment_id: nil}
    msg = %Broadcast{event: "deployments/update", payload: payload}
    assert {:noreply, ^state} = DeviceLink.handle_info(msg, state)
    assert_receive {:push, "update", ^payload}
  end

  test "ignores deployments/update broadcasts" do
    state = %DeviceLink.State{}
    msg = %Broadcast{event: "deployments/update"}
    assert {:noreply, ^state} = DeviceLink.handle_info(msg, state)
  end

  test "pushes update from deployment orchestrator", context do
    %{device: device, deployment: deployment, firmware: firmware} = create_device(context)
    new_meta = %{Map.from_struct(device.firmware_metadata) | uuid: Ecto.UUID.generate()}

    assert {:ok, device} =
             Devices.update_device(device, %{
               deployment_id: deployment.id,
               firmware_metadata: new_meta
             })

    # Prep the deployment to resolve
    assert {:ok, deployment} =
             NervesHub.Deployments.update_deployment(deployment, %{
               is_active: true,
               conditions: %{"tags" => device.tags, "version" => ""}
             })

    assert {:ok, inflight} = Devices.told_to_update(device, deployment)
    assert inflight.status == "pending"

    test_pid = self()
    push_cb = fn e, p -> send(test_pid, {:push, e, p}) end
    state = %DeviceLink.State{device: device, push_cb: push_cb}

    assert {:noreply, ^state} = DeviceLink.handle_info({"deployments/update", inflight}, state)

    assert Repo.reload(inflight).status == "updating"

    assert Enum.find(AuditLogs.logs_for(device), fn al ->
             al.description ==
               "deployment #{deployment.name} update triggered device #{device.identifier} to update firmware #{firmware.uuid}"
           end)

    assert_receive {:push, "update", %{update_available: true}}
  end

  test "moved device resolves potential deployment change", context do
    %{device: device, deployment: deployment} = create_device(context)
    # Prep the deployment to resolve
    assert {:ok, deployment} =
             NervesHub.Deployments.update_deployment(deployment, %{
               is_active: true,
               conditions: %{"tags" => device.tags, "version" => ""}
             })

    refute device.deployment_id

    state = %DeviceLink.State{device: device, deployment_channel: "deployment:none"}
    assert {:noreply, updated} = DeviceLink.handle_info(%Broadcast{event: "moved"}, state)
    assert updated.device.deployment_id == deployment.id
    assert updated.deployment_channel == "deployment:#{deployment.id}"

    assert Enum.find(AuditLogs.logs_for(device), fn al ->
             al.description ==
               "device #{device.identifier} reloaded deployment and is attached to deployment #{deployment.name}"
           end)
  end

  test "device change updates state and presence", context do
    %{device: device, link: link} = create_device(context) |> start_device_link()

    # Let the link process finish booting
    _ = :sys.get_state(link)

    assert [{^link, %{updates_enabled: true}}] = Registry.lookup(Devices, device.id)
    assert {:ok, updated} = Devices.update_device(device, %{updates_enabled: false})
    assert updated != device
    assert %{device: ^updated} = :sys.get_state(link)
    assert [{^link, %{updates_enabled: false}}] = Registry.lookup(Devices, device.id)
  end

  test "device update can start penalty timer", context do
    %{device: device} = create_device(context)
    blocked_until = DateTime.utc_now() |> DateTime.add(3, :minute)
    assert {:ok, updated} = Devices.update_device(device, %{updates_blocked_until: blocked_until})
    state = %DeviceLink.State{device: updated, deployment_channel: "deployment:none"}
    assert {:noreply, state} = DeviceLink.handle_info(%Broadcast{event: "devices/updated"}, state)
    assert state.penalty_timer
  end

  test "all other broadcasts are pushed to device" do
    test_pid = self()
    state = %DeviceLink.State{push_cb: fn e, p -> send(test_pid, {:push, e, p}) end}

    broadcasts = [
      {"wat", "is_this"},
      {"howdy", "partner"},
      {"up", "huh?!"},
      {"dn", "where?!"}
    ]

    for {e, p} <- broadcasts do
      msg = %Broadcast{event: e, payload: p}
      assert {:noreply, ^state} = DeviceLink.handle_info(msg, state)
      assert_receive {:push, ^e, ^p}
    end
  end

  describe "penalty box check" do
    test "restarts penalty timer if updates disabled" do
      blocked_until = DateTime.utc_now() |> DateTime.add(3, :minute)
      device = %Device{updates_enabled: false, updates_blocked_until: blocked_until}
      state = %DeviceLink.State{device: device}
      refute state.penalty_timer
      assert {:noreply, updated} = DeviceLink.handle_info(:penalty_box_check, state)
      assert updated.penalty_timer
    end

    test "does not set timer if blocked_until time in the past" do
      blocked_until = DateTime.utc_now() |> DateTime.add(-3, :minute)
      device = %Device{updates_enabled: false, updates_blocked_until: blocked_until}
      state = %DeviceLink.State{device: device}
      refute state.penalty_timer
      assert {:noreply, ^state} = DeviceLink.handle_info(:penalty_box_check, state)
    end

    test "does not set timer if no updates_blocked_until time" do
      device = %Device{updates_enabled: false}
      state = %DeviceLink.State{device: device}
      refute state.penalty_timer
      assert {:noreply, ^state} = DeviceLink.handle_info(:penalty_box_check, state)
    end

    test "updates device presence" do
      device = %Device{id: 1, updates_enabled: true}
      Registry.register(Devices, device.id, %{updates_enabled: false})
      state = %DeviceLink.State{device: device}
      refute state.penalty_timer
      assert {:noreply, ^state} = DeviceLink.handle_info(:penalty_box_check, state)

      test_pid = self()
      assert [{^test_pid, %{updates_enabled: true}}] = Registry.lookup(Devices, device.id)
    end
  end

  test "reconnect_timer expiration closes the link" do
    assert {:stop, :normal, %{}} = DeviceLink.handle_info(:timeout_reconnect, %{})
  end

  test "ignores unknown messages" do
    log =
      ExUnit.CaptureLog.capture_log(fn ->
        # Prob good spot for prop test
        DeviceLink.handle_info(12355, %{})
        DeviceLink.handle_info("12355", %{})
        DeviceLink.handle_info(:wat, %{})
        DeviceLink.handle_info(nil, %{})
      end)

    assert log =~ ~r/Unhandled message!/
  end

  defp create_device(context) do
    user = context[:user] || Fixtures.user_fixture()
    org = context[:org] || Fixtures.org_fixture(user)
    product = context[:product] || Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org)

    firmware =
      context[:firmware] || Fixtures.firmware_fixture(org_key, product, %{version: "0.0.1"})

    deployment =
      context[:deployment] ||
        Fixtures.deployment_fixture(org, firmware)
        |> Map.put(:firmware, firmware)

    params = %{
      identifier: context[:identifier] || to_string(context.test),
      tags: context[:tags] || ["beta", "beta-edge"]
    }

    device =
      Fixtures.device_fixture(
        org,
        product,
        firmware,
        params
      )

    %{
      deployment: deployment,
      device: device,
      firmware: firmware,
      org: org,
      product: product,
      user: user
    }
  end

  defp start_device_link(context) do
    link = start_supervised!({DeviceLink, context.device}, restart: :temporary)
    Mox.allow(NervesHub.UploadMock, self(), link)
    Map.put(context, :link, link)
  end
end
