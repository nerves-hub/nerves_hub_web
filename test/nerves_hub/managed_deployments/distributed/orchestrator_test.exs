defmodule NervesHub.ManagedDeployments.Distributed.OrchestratorTest do
  use NervesHub.DataCase, async: false

  use Mimic

  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.FirmwareDelta
  alias NervesHub.Firmwares.UpdateTool.Fwup
  alias NervesHub.Firmwares.Upload.File
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Distributed.Orchestrator
  alias NervesHub.Repo

  alias Phoenix.Socket.Broadcast

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)

    {:ok, deployment_group} =
      Fixtures.deployment_group_fixture(firmware, %{is_active: true})
      |> ManagedDeployments.update_deployment_group_status(:ready)

    device = Fixtures.device_fixture(org, product, firmware, %{status: :provisioned})
    device2 = Fixtures.device_fixture(org, product, firmware, %{status: :provisioned})
    device3 = Fixtures.device_fixture(org, product, firmware, %{status: :provisioned})

    {:ok,
     %{
       user: user,
       org: org,
       org_key: org_key,
       firmware: firmware,
       device: device,
       device2: device2,
       device3: device3,
       deployment_group: deployment_group,
       product: product
     }}
  end

  test "the concurrent_limit is respected", %{
    product: product,
    deployment_group: deployment_group,
    org_key: org_key,
    device: device1,
    device2: device2,
    device3: device3,
    user: user
  } do
    # setup deployment group, listen for broadcasts, and start the orchestrator
    firmware = Fixtures.firmware_fixture(org_key, product)

    {:ok, deployment_group} =
      ManagedDeployments.update_deployment_group(
        deployment_group,
        %{
          concurrent_updates: 2,
          firmware_id: firmware.id
        },
        user
      )

    {:ok, _pid} =
      start_supervised(%{
        id: "Orchestrator##{deployment_group.id}",
        start: {Orchestrator, :start_link, [deployment_group, false]},
        restart: :temporary
      })

    # assign a device to the deployment and mark it as 'connected'
    topic1 = "device:#{device1.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, topic1)

    device1 = Devices.update_deployment_group(device1, deployment_group)
    {:ok, connection} = Connections.device_connecting(device1, device1.product_id)
    :ok = Connections.device_connected(device1, connection.id)
    Devices.deployment_device_online(device1)

    # sent when a device is a assigned a deployment group
    assert_receive %Broadcast{topic: ^topic1, event: "deployment_updated"}, 500

    # check that the first device was told to update
    assert_receive %Broadcast{topic: ^topic1, event: "update"}, 500

    # assign a second device to the deployment group and mark it as connected
    topic2 = "device:#{device2.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, topic2)

    device2 = Devices.update_deployment_group(device2, deployment_group)
    {:ok, connection} = Connections.device_connecting(device2, device2.product_id)
    :ok = Connections.device_connected(device2, connection.id)
    Devices.deployment_device_online(device2)

    # and check that device2 was told to update
    assert_receive %Broadcast{topic: ^topic2, event: "update"}, 500

    # and now assign a third device to the deployment group and mark it as connected
    topic3 = "device:#{device3.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, topic3)

    device3 = Devices.update_deployment_group(device3, deployment_group)
    {:ok, connection} = Connections.device_connecting(device3, device3.product_id)
    :ok = Connections.device_connected(device3, connection.id)
    Devices.deployment_device_online(device3)

    # and check that device3 isn't told to update as the concurrent limit has been reached
    refute_receive %Broadcast{topic: ^topic3, event: "update"}, 500
  end

  test "finds another device to update when a device finishes updating", %{
    product: product,
    deployment_group: deployment_group,
    org_key: org_key,
    device: device,
    device2: device2,
    user: user
  } do
    # only allow for 1 update at a time
    {:ok, deployment_group} =
      ManagedDeployments.update_deployment_group(deployment_group, %{concurrent_updates: 1}, user)

    device = Devices.update_deployment_group(device, deployment_group)
    {:ok, connection} = Connections.device_connecting(device, device.product_id)
    :ok = Connections.device_connected(device, connection.id)

    device2 = Devices.update_deployment_group(device2, deployment_group)
    {:ok, connection} = Connections.device_connecting(device2, device2.product_id)
    :ok = Connections.device_connected(device2, connection.id)

    topic1 = "device:#{device.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, topic1)

    topic2 = "device:#{device2.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, topic2)

    deployment_group_topic = "orchestrator:deployment:#{deployment_group.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, deployment_group_topic)

    {:ok, pid} =
      start_supervised(%{
        id: "Orchestrator##{deployment_group.id}",
        start: {Orchestrator, :start_link, [deployment_group, false]},
        restart: :temporary
      })

    # create new firmware and update the deployment group with it
    firmware = Fixtures.firmware_fixture(org_key, product)

    {:ok, _deployment_group} =
      ManagedDeployments.update_deployment_group(deployment_group, %{firmware_id: firmware.id}, user)

    # check that the first device was told to update
    assert_receive %Broadcast{topic: ^topic1, event: "update"}, 500

    # bring the second device 'online'
    Devices.update_deployment_group(device2, deployment_group)
    {:ok, connection} = Connections.device_connecting(device2, device2.product_id)
    :ok = Connections.device_connected(device2, connection.id)

    # sent by the device after its updated
    assert_receive %Broadcast{topic: ^topic2, event: "deployment_updated"}, 500

    # pretend that the first device successfully updated
    {:ok, device} =
      Devices.update_device(device, %{firmware_metadata: %{"uuid" => firmware.uuid}})

    Devices.firmware_update_successful(device, device.firmware_metadata)

    # sent by the device after its updated
    assert_receive %Broadcast{topic: ^topic1, event: "updated"}, 500

    # check that the orchestrator was told about the successful update
    assert_receive %Broadcast{topic: ^deployment_group_topic, event: "device-updated"}, 500

    # and that device2 was told to update
    assert_receive %Broadcast{topic: ^topic2, event: "update"}, 500

    :sys.get_state(pid)
  end

  test "doesn't try to update devices whos firmware is not validated", %{
    product: product,
    deployment_group: deployment_group,
    org_key: org_key,
    device: device,
    user: user
  } do
    # only allow for 1 update at a time
    {:ok, deployment_group} =
      ManagedDeployments.update_deployment_group(deployment_group, %{concurrent_updates: 1}, user)

    device = Devices.update_deployment_group(device, deployment_group)
    {:ok, device} = Devices.update_device(device, %{firmware_validation_status: "not_validated"})
    {:ok, connection} = Connections.device_connecting(device, device.product_id)
    :ok = Connections.device_connected(device, connection.id)

    topic1 = "device:#{device.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, topic1)

    deployment_group_topic = "orchestrator:deployment:#{deployment_group.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, deployment_group_topic)

    {:ok, _pid} =
      start_supervised(%{
        id: "Orchestrator##{deployment_group.id}",
        start: {Orchestrator, :start_link, [deployment_group, false]},
        restart: :temporary
      })

    # create new firmware and update the deployment group with it
    firmware = Fixtures.firmware_fixture(org_key, product)

    {:ok, _deployment_group} =
      ManagedDeployments.update_deployment_group(deployment_group, %{firmware_id: firmware.id}, user)

    # check that the device is not told to update
    refute_receive %Broadcast{topic: ^topic1, event: "update"}, 1_000
  end

  test "the orchestrator doesn't 'trigger' if the device that came online is up-to-date", %{
    deployment_group: deployment_group,
    org_key: org_key,
    product: product,
    device: device1,
    device2: device2,
    user: user
  } do
    # An ugly set of expectations
    # `Devices.available_for_update` should be called:
    # - once upon Orchestrator startup
    # - once for when an out of date device comes online
    # - and no more times after that
    Devices
    |> expect(:available_for_update, 1, fn _deployment_group, _slots ->
      []
    end)
    |> expect(:available_for_update, 1, fn _deployment_group, _slots ->
      [device1]
    end)
    |> reject(:available_for_update, 2)

    firmware = Fixtures.firmware_fixture(org_key, product)

    {:ok, deployment_group} =
      ManagedDeployments.update_deployment_group(
        deployment_group,
        %{
          concurrent_updates: 2,
          firmware_id: firmware.id
        },
        user
      )

    deployment_group_topic = "orchestrator:deployment:#{deployment_group.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, deployment_group_topic)

    {:ok, pid} =
      start_supervised(%{
        id: "Orchestrator##{deployment_group.id}",
        start: {Orchestrator, :start_link, [deployment_group, false]},
        restart: :temporary
      })

    allow(Devices, self(), pid)

    # only one device in this test isn't using the same firmware as the deployment group
    # the `Devices.available_for_update/2` function should only be called once by device1

    # assign device1 to the deployment group and mark it as 'connected'
    # this device will be told to update
    device1_topic = "device:#{device1.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, device1_topic)

    device1 = Devices.update_deployment_group(device1, deployment_group)

    {:ok, connection} = Connections.device_connecting(device1, device1.product_id)
    :ok = Connections.device_connected(device1, connection.id)

    Devices.deployment_device_online(device1)

    # sent when a device is assigned a deployment group
    assert_receive %Broadcast{topic: ^device1_topic, event: "deployment_updated"},
                   500

    # the orchestrator is told that a device assigned to it is online
    assert_receive %Broadcast{topic: ^deployment_group_topic, event: "device-online"}, 500

    # and then a device is told to schedule an update
    assert_receive %Broadcast{topic: ^device1_topic, event: "update"}, 1_000

    Mimic.reject(&Devices.available_for_update/2)

    # device2 is already on the latest firmware, so when it comes online
    # `Devices.available_for_update/2` won't be called and the device won't
    # be told to update
    device2_topic = "device:#{device2.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, device2_topic)

    {:ok, device2} =
      Devices.update_device(device2, %{firmware_metadata: %{"uuid" => firmware.uuid}})

    device2 = Devices.update_deployment_group(device2, deployment_group)
    {:ok, connection} = Connections.device_connecting(device2, device2.product_id)
    :ok = Connections.device_connected(device2, connection.id)
    Devices.deployment_device_online(device2)

    assert_receive %Broadcast{topic: ^deployment_group_topic, event: "device-online"}, 500
    refute_receive %Broadcast{topic: ^device2_topic, event: "update"}, 500

    # allows for db connections to finish and close
    :sys.get_state(pid)
  end

  test "the orchestrator is 'triggered' when a device is reenabled to accept updates", %{
    user: user,
    deployment_group: deployment_group,
    org_key: org_key,
    product: product,
    device: device1
  } do
    firmware = Fixtures.firmware_fixture(org_key, product)

    {:ok, deployment_group} =
      ManagedDeployments.update_deployment_group(
        deployment_group,
        %{
          concurrent_updates: 2,
          firmware_id: firmware.id
        },
        user
      )

    deployment_topic = "orchestrator:deployment:#{deployment_group.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, deployment_topic)

    {:ok, pid} =
      start_supervised(%{
        id: "Orchestrator##{deployment_group.id}",
        start: {Orchestrator, :start_link, [deployment_group, false]},
        restart: :temporary
      })

    # assign device1 to the deployment group and mark it as 'connected'
    # this device will be told to update
    device1_topic = "device:#{device1.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, device1_topic)

    device1 = Devices.update_deployment_group(device1, deployment_group)
    {:ok, device1} = Devices.update_device(device1, %{updates_enabled: false})

    {:ok, connection} = Connections.device_connecting(device1, device1.product_id)
    :ok = Connections.device_connected(device1, connection.id)

    Devices.deployment_device_online(device1)

    # sent when a device is assigned a deployment group
    assert_receive %Broadcast{topic: ^device1_topic, event: "deployment_updated"},
                   500

    # the orchestrator is told that a device assigned to it is online
    assert_receive %Broadcast{topic: ^deployment_topic, event: "device-online"}, 500

    # the device isn't told to update, yet
    refute_receive %Broadcast{topic: ^device1_topic, event: "update"}, 1_000

    # we enable updates for the device
    Devices.enable_updates(device1, user)

    # and then a device is told to schedule an update
    assert_receive %Broadcast{topic: ^device1_topic, event: "update"}, 1_000

    # allows for db connections to finish and close
    :sys.get_state(pid)
  end

  test "shuts down if the deployment group is no longer active", %{
    deployment_group: deployment_group
  } do
    {:ok, pid} =
      start_supervised(%{
        id: "Orchestrator##{deployment_group.id}",
        start: {Orchestrator, :start_link, [deployment_group, false]},
        restart: :temporary
      })

    Process.monitor(pid)

    ManagedDeployments.deployment_deactivated_event(deployment_group)

    assert_receive {:DOWN, _reference, :process, ^pid, :normal}, 500
  end

  test "shuts down if the deployment deleted", %{deployment_group: deployment_group} do
    {:ok, pid} =
      start_supervised(%{
        id: "Orchestrator##{deployment_group.id}",
        start: {Orchestrator, :start_link, [deployment_group, false]},
        restart: :temporary
      })

    Process.monitor(pid)

    ManagedDeployments.delete_deployment_group(deployment_group)

    assert_receive {:DOWN, _reference, :process, ^pid, :normal}, 3_000
  end

  @tag :tmp_dir
  test "triggers update and sets deployment group status to ready when delta completes", %{
    deployment_group: deployment_group,
    org: org,
    org_key: org_key,
    product: product,
    tmp_dir: tmp_dir
  } do
    source_firmware = Fixtures.firmware_fixture(org_key, product)
    deployment_group = Ecto.Changeset.change(deployment_group, %{status: :preparing}) |> Repo.update!()
    Fixtures.device_fixture(org, product, source_firmware, %{deployment_id: deployment_group.id})
    delta = Fixtures.firmware_delta_fixture(source_firmware, deployment_group.firmware, %{status: :processing})

    expect(Fwup, :create_firmware_delta_file, fn _, _ ->
      {:ok,
       %{
         tool: "fwup",
         size: "1000",
         source_size: "2000",
         target_size: "3000",
         filepath: tmp_dir,
         tool_metadata: %{}
       }}
    end)

    expect(File, :upload_file, fn _, _ -> :ok end)

    expect(Devices, :available_for_update, 2, fn _, _ -> [] end)

    {:ok, pid} =
      start_supervised(%{
        id: "Orchestrator##{deployment_group.id}",
        start: {Orchestrator, :start_link, [deployment_group, false]},
        restart: :temporary
      })

    allow(Devices, self(), pid)

    :ok = Firmwares.generate_firmware_delta(delta, source_firmware, deployment_group.firmware)
    assert %{deployment_group: %{status: :ready}} = :sys.get_state(pid)
  end

  test "handles delta subscriptions when firmware changes", %{
    deployment_group: deployment_group,
    org_key: org_key,
    product: product,
    user: user
  } do
    new_firmware = %{id: new_firmware_id} = Fixtures.firmware_fixture(org_key, product)
    %{firmware_id: old_firmware_id} = deployment_group

    {:ok, pid} =
      start_supervised(%{
        id: "Orchestrator##{deployment_group.id}",
        start: {Orchestrator, :start_link, [deployment_group, false]},
        restart: :temporary
      })

    allow(Firmwares, self(), pid)

    expect(Firmwares, :unsubscribe_firmware_delta_target, fn ^old_firmware_id -> :ok end)
    expect(Firmwares, :subscribe_firmware_delta_target, fn ^new_firmware_id -> :ok end)

    {:ok, _} = ManagedDeployments.update_deployment_group(deployment_group, %{firmware_id: new_firmware.id}, user)
    _ = :sys.get_state(pid)
  end

  test "updating deployment group to active waits for deltas to be ready", %{
    deployment_group: deployment_group,
    org_key: org_key,
    product: product,
    org: org,
    user: user
  } do
    other_firmware = Fixtures.firmware_fixture(org_key, product)

    device =
      Fixtures.device_fixture(org, product, other_firmware)
      |> Devices.update_deployment_group(deployment_group)

    {:ok, connection} = Connections.device_connecting(device, device.product_id)
    :ok = Connections.device_connected(device, connection.id)

    deployment_group =
      Ecto.Changeset.change(deployment_group, %{is_active: false, delta_updatable: true}) |> Repo.update!()

    {:ok, pid} =
      start_supervised(%{
        id: "Orchestrator##{deployment_group.id}",
        start: {Orchestrator, :start_link, [deployment_group, false]},
        restart: :temporary
      })

    reject(&Devices.available_for_update/2)

    allow(Devices, self(), pid)

    {:ok, _} = ManagedDeployments.update_deployment_group(deployment_group, %{is_active: true}, user)
    _ = :sys.get_state(pid)
  end

  describe "trigger_update/1" do
    test "ignores updates when deployment_group is inactive", %{deployment_group: deployment_group} do
      reject(&Devices.available_for_update/2)
      reject(&Orchestrator.schedule_devices!/2)

      Orchestrator.trigger_update(%{deployment_group | is_active: false})
    end

    test "sets deployment group status to :ready if all associated deltas are ready", %{
      deployment_group: deployment_group,
      org_key: org_key,
      org: org,
      product: product,
      firmware: firmware
    } do
      firmware2 = Fixtures.firmware_fixture(org_key, product)
      firmware3 = Fixtures.firmware_fixture(org_key, product)
      firmware4 = Fixtures.firmware_fixture(org_key, product)

      _ =
        Fixtures.device_fixture(org, product, firmware2)
        |> Devices.update_deployment_group(deployment_group)

      _ =
        Fixtures.device_fixture(org, product, firmware3)
        |> Devices.update_deployment_group(deployment_group)

      _ =
        Fixtures.device_fixture(org, product, firmware4)
        |> Devices.update_deployment_group(deployment_group)

      _ = Fixtures.firmware_delta_fixture(firmware2, firmware)
      _ = Fixtures.firmware_delta_fixture(firmware3, firmware)
      delta_processing = Fixtures.firmware_delta_fixture(firmware4, firmware, %{status: :processing})
      deployment_group = Ecto.Changeset.change(deployment_group, %{status: :preparing}) |> Repo.update!()
      assert %{status: :preparing} = Orchestrator.trigger_update(deployment_group)

      _ = Ecto.Changeset.change(delta_processing, %{status: :completed}) |> Repo.update!()

      assert %{status: :ready} = Orchestrator.trigger_update(deployment_group)
    end

    test "triggers delta generation and sets deployment group status to :preparing", %{
      deployment_group: deployment_group,
      org_key: org_key,
      org: org,
      product: product
    } do
      refute Repo.exists?(FirmwareDelta)
      firmware2 = Fixtures.firmware_fixture(org_key, product)

      _ =
        Fixtures.device_fixture(org, product, firmware2)
        |> Devices.update_deployment_group(deployment_group)

      assert %{status: :preparing} =
               Orchestrator.trigger_update(%{deployment_group | delta_updatable: true})

      assert Repo.exists?(FirmwareDelta)
    end

    test "doesn't update deployment group status to :preparing if no deltas are generated", %{
      deployment_group: deployment_group
    } do
      assert deployment_group.status == :ready
      refute deployment_group.delta_updatable

      reject(&ManagedDeployments.trigger_delta_generation_for_deployment_group/1)
      assert %{status: :ready} = Orchestrator.trigger_update(deployment_group)
    end

    test "doesn't triggers delta generation when deployment group status is :preparing", %{
      deployment_group: deployment_group
    } do
      Orchestrator.trigger_update(%{deployment_group | status: :preparing})
      refute Repo.exists?(FirmwareDelta)
    end
  end

  describe "priority queue" do
    test "processes priority queue devices first", %{
      deployment_group: deployment_group,
      product: product,
      org: org,
      firmware: firmware,
      user: user
    } do
      # Preload org and enable priority queue
      deployment_group = Repo.preload(deployment_group, :org)

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(
          deployment_group,
          %{
            priority_queue_enabled: true,
            priority_queue_concurrent_updates: 2,
            priority_queue_firmware_version_threshold: "1.0.0",
            concurrent_updates: 1
          },
          user
        )

      deployment_group = Repo.preload(deployment_group, :org, force: true)

      # Create devices with different firmware versions
      old_device1 = Fixtures.device_fixture(org, product, firmware, %{tags: [], identifier: "old_device_1"})
      old_device2 = Fixtures.device_fixture(org, product, firmware, %{tags: [], identifier: "old_device_2"})
      new_device = Fixtures.device_fixture(org, product, firmware, %{tags: [], identifier: "new_device"})

      {:ok, old_device1} =
        Devices.update_firmware_metadata(
          old_device1,
          %{"version" => "0.9.0", "uuid" => Ecto.UUID.generate()},
          :unknown,
          false
        )

      {:ok, old_device2} =
        Devices.update_firmware_metadata(
          old_device2,
          %{"version" => "0.8.0", "uuid" => Ecto.UUID.generate()},
          :unknown,
          false
        )

      {:ok, new_device} =
        Devices.update_firmware_metadata(
          new_device,
          %{"version" => "1.5.0", "uuid" => Ecto.UUID.generate()},
          :unknown,
          false
        )

      old_device1 = Devices.update_deployment_group(old_device1, deployment_group)
      old_device2 = Devices.update_deployment_group(old_device2, deployment_group)
      new_device = Devices.update_deployment_group(new_device, deployment_group)

      {:ok, conn1} = Connections.device_connecting(old_device1, product.id)
      {:ok, conn2} = Connections.device_connecting(old_device2, product.id)
      {:ok, conn3} = Connections.device_connecting(new_device, product.id)

      :ok = Connections.device_connected(old_device1, conn1.id)
      :ok = Connections.device_connected(old_device2, conn2.id)
      :ok = Connections.device_connected(new_device, conn3.id)

      # Test logic
      old_device1_topic = "device:#{old_device1.id}"
      old_device2_topic = "device:#{old_device2.id}"
      new_device_topic = "device:#{new_device.id}"

      Phoenix.PubSub.subscribe(NervesHub.PubSub, old_device1_topic)
      Phoenix.PubSub.subscribe(NervesHub.PubSub, old_device2_topic)
      Phoenix.PubSub.subscribe(NervesHub.PubSub, new_device_topic)

      Orchestrator.trigger_update(deployment_group)

      # Priority queue devices should get updates first
      # Receive all messages and verify priority queue devices were scheduled
      assert_receive %Broadcast{topic: topic1, event: "update"}, 1_000
      assert_receive %Broadcast{topic: topic2, event: "update"}, 1_000
      assert_receive %Broadcast{topic: topic3, event: "update"}, 1_000

      # Verify the priority queue devices were in the first two messages
      priority_topics = [old_device1_topic, old_device2_topic]
      assert topic1 in priority_topics
      assert topic2 in priority_topics
      # The normal queue device should be last
      assert topic3 == new_device_topic
    end

    test "available_priority_slots/1 calculates correctly", %{
      deployment_group: deployment_group,
      product: product,
      org: org,
      firmware: firmware,
      user: user
    } do
      deployment_group = Repo.preload(deployment_group, :org)

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(
          deployment_group,
          %{
            priority_queue_enabled: true,
            priority_queue_concurrent_updates: 2,
            priority_queue_firmware_version_threshold: "1.0.0"
          },
          user
        )

      deployment_group = Repo.preload(deployment_group, :org, force: true)

      old_device1 = Fixtures.device_fixture(org, product, firmware, %{tags: [], identifier: "old_device_1"})

      {:ok, old_device1} =
        Devices.update_firmware_metadata(
          old_device1,
          %{"version" => "0.9.0", "uuid" => Ecto.UUID.generate()},
          :unknown,
          false
        )

      old_device1 = Devices.update_deployment_group(old_device1, deployment_group)

      {:ok, conn1} = Connections.device_connecting(old_device1, product.id)
      :ok = Connections.device_connected(old_device1, conn1.id)
      assert Orchestrator.available_priority_slots(deployment_group) == 2

      # Add one device to priority queue
      {:ok, _} = Devices.told_to_update(old_device1, deployment_group, priority_queue: true)

      assert Orchestrator.available_priority_slots(deployment_group) == 1
    end

    test "priority and normal queues operate independently", %{
      deployment_group: deployment_group,
      product: product,
      org: org,
      firmware: firmware,
      user: user
    } do
      deployment_group = Repo.preload(deployment_group, :org)

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(
          deployment_group,
          %{
            priority_queue_enabled: true,
            priority_queue_concurrent_updates: 2,
            priority_queue_firmware_version_threshold: "1.0.0"
          },
          user
        )

      deployment_group = Repo.preload(deployment_group, :org, force: true)

      old_device1 = Fixtures.device_fixture(org, product, firmware, %{tags: [], identifier: "old_device_1"})
      new_device = Fixtures.device_fixture(org, product, firmware, %{tags: [], identifier: "new_device"})

      {:ok, old_device1} =
        Devices.update_firmware_metadata(
          old_device1,
          %{"version" => "0.9.0", "uuid" => Ecto.UUID.generate()},
          :unknown,
          false
        )

      {:ok, new_device} =
        Devices.update_firmware_metadata(
          new_device,
          %{"version" => "1.5.0", "uuid" => Ecto.UUID.generate()},
          :unknown,
          false
        )

      old_device1 = Devices.update_deployment_group(old_device1, deployment_group)
      new_device = Devices.update_deployment_group(new_device, deployment_group)

      {:ok, conn1} = Connections.device_connecting(old_device1, product.id)
      {:ok, conn2} = Connections.device_connecting(new_device, product.id)

      :ok = Connections.device_connected(old_device1, conn1.id)
      :ok = Connections.device_connected(new_device, conn2.id)
      # Fill priority queue
      {:ok, _} = Devices.told_to_update(old_device1, deployment_group, priority_queue: true)

      # Normal queue should still have full capacity
      assert Orchestrator.available_slots(deployment_group) == deployment_group.concurrent_updates

      # Fill normal queue partially
      {:ok, _} = Devices.told_to_update(new_device, deployment_group, priority_queue: false)

      # Priority queue should still have capacity
      assert Orchestrator.available_priority_slots(deployment_group) == 1
    end

    test "priority queue disabled by default", %{org: org, product: product, firmware: firmware} do
      {:ok, deployment_group} =
        Fixtures.deployment_group_fixture(firmware, %{name: "Priority Queue Test Disabled", is_active: true})
        |> ManagedDeployments.update_deployment_group_status(:ready)

      refute deployment_group.priority_queue_enabled

      device = Fixtures.device_fixture(org, product, firmware)

      {:ok, device} =
        Devices.update_firmware_metadata(
          device,
          %{"version" => "0.1.0", "uuid" => Ecto.UUID.generate()},
          :unknown,
          false
        )

      device = Devices.update_deployment_group(device, deployment_group)

      {:ok, conn} = Connections.device_connecting(device, product.id)
      :ok = Connections.device_connected(device, conn.id)

      # Should return empty list since priority queue is disabled
      assert Devices.available_for_priority_update(deployment_group, 10) == []
    end

    test "devices with version above threshold not eligible for priority queue", %{
      deployment_group: deployment_group,
      product: product,
      org: org,
      firmware: firmware,
      user: user
    } do
      deployment_group = Repo.preload(deployment_group, :org)

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(
          deployment_group,
          %{
            priority_queue_enabled: true,
            priority_queue_concurrent_updates: 2,
            priority_queue_firmware_version_threshold: "1.0.0"
          },
          user
        )

      new_device = Fixtures.device_fixture(org, product, firmware, %{tags: [], identifier: "new_device"})

      {:ok, new_device} =
        Devices.update_firmware_metadata(
          new_device,
          %{"version" => "1.5.0", "uuid" => Ecto.UUID.generate()},
          :unknown,
          false
        )

      new_device = Devices.update_deployment_group(new_device, deployment_group)

      {:ok, conn} = Connections.device_connecting(new_device, product.id)
      :ok = Connections.device_connected(new_device, conn.id)
      # new_device has version 1.5.0, threshold is 1.0.0
      available = Devices.available_for_priority_update(deployment_group, 10)
      refute Enum.any?(available, &(&1.id == new_device.id))
    end

    test "devices with version at or below threshold eligible for priority queue", %{
      deployment_group: deployment_group,
      product: product,
      org: org,
      firmware: firmware,
      user: user
    } do
      deployment_group = Repo.preload(deployment_group, :org)

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(
          deployment_group,
          %{
            priority_queue_enabled: true,
            priority_queue_concurrent_updates: 2,
            priority_queue_firmware_version_threshold: "1.0.0"
          },
          user
        )

      old_device1 = Fixtures.device_fixture(org, product, firmware, %{tags: [], identifier: "old_device_1"})
      old_device2 = Fixtures.device_fixture(org, product, firmware, %{tags: [], identifier: "old_device_2"})

      {:ok, old_device1} =
        Devices.update_firmware_metadata(
          old_device1,
          %{"version" => "0.9.0", "uuid" => Ecto.UUID.generate()},
          :unknown,
          false
        )

      {:ok, old_device2} =
        Devices.update_firmware_metadata(
          old_device2,
          %{"version" => "0.8.0", "uuid" => Ecto.UUID.generate()},
          :unknown,
          false
        )

      old_device1 = Devices.update_deployment_group(old_device1, deployment_group)
      old_device2 = Devices.update_deployment_group(old_device2, deployment_group)

      {:ok, conn1} = Connections.device_connecting(old_device1, product.id)
      {:ok, conn2} = Connections.device_connecting(old_device2, product.id)

      :ok = Connections.device_connected(old_device1, conn1.id)
      :ok = Connections.device_connected(old_device2, conn2.id)
      # old devices have versions 0.9.0 and 0.8.0, threshold is 1.0.0
      available = Devices.available_for_priority_update(deployment_group, 10)
      device_ids = Enum.map(available, & &1.id)

      assert old_device1.id in device_ids
      assert old_device2.id in device_ids
    end

    test "count_inflight_priority_updates_for/1 counts only priority queue updates", %{
      deployment_group: deployment_group,
      product: product,
      org: org,
      firmware: firmware,
      user: user
    } do
      deployment_group = Repo.preload(deployment_group, :org)

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(
          deployment_group,
          %{
            priority_queue_enabled: true,
            priority_queue_concurrent_updates: 2,
            priority_queue_firmware_version_threshold: "1.0.0"
          },
          user
        )

      deployment_group = Repo.preload(deployment_group, :org, force: true)

      old_device1 = Fixtures.device_fixture(org, product, firmware, %{tags: [], identifier: "old_device_1"})
      old_device2 = Fixtures.device_fixture(org, product, firmware, %{tags: [], identifier: "old_device_2"})
      new_device = Fixtures.device_fixture(org, product, firmware, %{tags: [], identifier: "new_device"})

      {:ok, old_device1} =
        Devices.update_firmware_metadata(
          old_device1,
          %{"version" => "0.9.0", "uuid" => Ecto.UUID.generate()},
          :unknown,
          false
        )

      {:ok, old_device2} =
        Devices.update_firmware_metadata(
          old_device2,
          %{"version" => "0.8.0", "uuid" => Ecto.UUID.generate()},
          :unknown,
          false
        )

      {:ok, new_device} =
        Devices.update_firmware_metadata(
          new_device,
          %{"version" => "1.5.0", "uuid" => Ecto.UUID.generate()},
          :unknown,
          false
        )

      old_device1 = Devices.update_deployment_group(old_device1, deployment_group)
      old_device2 = Devices.update_deployment_group(old_device2, deployment_group)
      new_device = Devices.update_deployment_group(new_device, deployment_group)

      {:ok, conn1} = Connections.device_connecting(old_device1, product.id)
      {:ok, conn2} = Connections.device_connecting(old_device2, product.id)
      {:ok, conn3} = Connections.device_connecting(new_device, product.id)

      :ok = Connections.device_connected(old_device1, conn1.id)
      :ok = Connections.device_connected(old_device2, conn2.id)
      :ok = Connections.device_connected(new_device, conn3.id)
      assert Devices.count_inflight_priority_updates_for(deployment_group) == 0

      {:ok, _} = Devices.told_to_update(old_device1, deployment_group, priority_queue: true)
      assert Devices.count_inflight_priority_updates_for(deployment_group) == 1

      {:ok, _} = Devices.told_to_update(new_device, deployment_group, priority_queue: false)
      # Should still be 1, not counting normal queue
      assert Devices.count_inflight_priority_updates_for(deployment_group) == 1

      {:ok, _} = Devices.told_to_update(old_device2, deployment_group, priority_queue: true)
      assert Devices.count_inflight_priority_updates_for(deployment_group) == 2
    end

    test "count_inflight_updates_for/1 counts only normal queue updates", %{
      deployment_group: deployment_group,
      product: product,
      org: org,
      firmware: firmware,
      user: user
    } do
      deployment_group = Repo.preload(deployment_group, :org)

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(
          deployment_group,
          %{
            priority_queue_enabled: true,
            priority_queue_concurrent_updates: 2,
            priority_queue_firmware_version_threshold: "1.0.0"
          },
          user
        )

      deployment_group = Repo.preload(deployment_group, :org, force: true)

      old_device1 = Fixtures.device_fixture(org, product, firmware, %{tags: [], identifier: "old_device_1"})
      new_device = Fixtures.device_fixture(org, product, firmware, %{tags: [], identifier: "new_device"})

      {:ok, old_device1} =
        Devices.update_firmware_metadata(
          old_device1,
          %{"version" => "0.9.0", "uuid" => Ecto.UUID.generate()},
          :unknown,
          false
        )

      {:ok, new_device} =
        Devices.update_firmware_metadata(
          new_device,
          %{"version" => "1.5.0", "uuid" => Ecto.UUID.generate()},
          :unknown,
          false
        )

      old_device1 = Devices.update_deployment_group(old_device1, deployment_group)
      new_device = Devices.update_deployment_group(new_device, deployment_group)

      {:ok, conn1} = Connections.device_connecting(old_device1, product.id)
      {:ok, conn2} = Connections.device_connecting(new_device, product.id)

      :ok = Connections.device_connected(old_device1, conn1.id)
      :ok = Connections.device_connected(new_device, conn2.id)
      assert Devices.count_inflight_updates_for(deployment_group) == 0

      {:ok, _} = Devices.told_to_update(new_device, deployment_group, priority_queue: false)
      assert Devices.count_inflight_updates_for(deployment_group) == 1

      {:ok, _} = Devices.told_to_update(old_device1, deployment_group, priority_queue: true)
      # Should still be 1, not counting priority queue
      assert Devices.count_inflight_updates_for(deployment_group) == 1
    end

    test "priority queue empty when threshold is nil", %{org: org, product: product, firmware: firmware, user: user} do
      {:ok, deployment_group} =
        Fixtures.deployment_group_fixture(firmware, %{name: "Priority Queue Test Nil", is_active: true})
        |> ManagedDeployments.update_deployment_group(
          %{
            priority_queue_enabled: true,
            priority_queue_firmware_version_threshold: nil
          },
          user
        )

      device = Fixtures.device_fixture(org, product, firmware)

      {:ok, device} =
        Devices.update_firmware_metadata(
          device,
          %{"version" => "0.1.0", "uuid" => Ecto.UUID.generate()},
          :unknown,
          false
        )

      device = Devices.update_deployment_group(device, deployment_group)

      {:ok, conn} = Connections.device_connecting(device, product.id)
      :ok = Connections.device_connected(device, conn.id)

      assert Devices.available_for_priority_update(deployment_group, 10) == []
    end

    test "priority queue empty when threshold is empty string", %{
      deployment_group: deployment_group,
      product: product,
      org: org,
      firmware: firmware,
      user: user
    } do
      deployment_group = Repo.preload(deployment_group, :org)

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(
          deployment_group,
          %{
            priority_queue_enabled: true,
            priority_queue_firmware_version_threshold: ""
          },
          user
        )

      device = Fixtures.device_fixture(org, product, firmware)

      {:ok, device} =
        Devices.update_firmware_metadata(
          device,
          %{"version" => "0.1.0", "uuid" => Ecto.UUID.generate()},
          :unknown,
          false
        )

      device = Devices.update_deployment_group(device, deployment_group)

      {:ok, conn} = Connections.device_connecting(device, product.id)
      :ok = Connections.device_connected(device, conn.id)

      assert Devices.available_for_priority_update(deployment_group, 10) == []
    end

    test "correctly handles semantic versioning with double-digit minor/patch versions", %{
      deployment_group: deployment_group,
      product: product,
      org: org,
      firmware: firmware,
      user: user
    } do
      deployment_group = Repo.preload(deployment_group, :org)

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(
          deployment_group,
          %{
            priority_queue_enabled: true,
            priority_queue_concurrent_updates: 10,
            priority_queue_firmware_version_threshold: "1.2.0"
          },
          user
        )

      # Create devices with versions that test semantic versioning
      # String comparison would say "1.10.0" < "1.2.0" (WRONG!)
      device_1_10 = Fixtures.device_fixture(org, product, firmware, %{tags: [], identifier: "device_1_10"})
      # String comparison would say "1.9.0" > "1.2.0" (correct by accident)
      device_1_9 = Fixtures.device_fixture(org, product, firmware, %{tags: [], identifier: "device_1_9"})
      # This one should definitely be excluded
      device_2_0 = Fixtures.device_fixture(org, product, firmware, %{tags: [], identifier: "device_2_0"})
      # This one should be included (1.1.0 <= 1.2.0)
      device_1_1 = Fixtures.device_fixture(org, product, firmware, %{tags: [], identifier: "device_1_1"})

      # Ensure devices have different firmware UUIDs from the target firmware
      # so they'll be considered for updates
      old_firmware_uuid = Ecto.UUID.generate()

      {:ok, device_1_10} =
        Devices.update_firmware_metadata(
          device_1_10,
          %{"version" => "1.10.0", "uuid" => old_firmware_uuid},
          :validated,
          false
        )

      {:ok, device_1_9} =
        Devices.update_firmware_metadata(
          device_1_9,
          %{"version" => "1.9.0", "uuid" => old_firmware_uuid},
          :validated,
          false
        )

      {:ok, device_2_0} =
        Devices.update_firmware_metadata(
          device_2_0,
          %{"version" => "2.0.0", "uuid" => old_firmware_uuid},
          :validated,
          false
        )

      {:ok, device_1_1} =
        Devices.update_firmware_metadata(
          device_1_1,
          %{"version" => "1.1.0", "uuid" => old_firmware_uuid},
          :validated,
          false
        )

      device_1_10 = Devices.update_deployment_group(device_1_10, deployment_group)
      device_1_9 = Devices.update_deployment_group(device_1_9, deployment_group)
      device_2_0 = Devices.update_deployment_group(device_2_0, deployment_group)
      device_1_1 = Devices.update_deployment_group(device_1_1, deployment_group)

      {:ok, conn1} = Connections.device_connecting(device_1_10, product.id)
      {:ok, conn2} = Connections.device_connecting(device_1_9, product.id)
      {:ok, conn3} = Connections.device_connecting(device_2_0, product.id)
      {:ok, conn4} = Connections.device_connecting(device_1_1, product.id)

      :ok = Connections.device_connected(device_1_10, conn1.id)
      :ok = Connections.device_connected(device_1_9, conn2.id)
      :ok = Connections.device_connected(device_2_0, conn3.id)
      :ok = Connections.device_connected(device_1_1, conn4.id)

      available = Devices.available_for_priority_update(deployment_group, 10)
      device_ids = Enum.map(available, & &1.id)

      # With proper semantic versioning:
      # 1.1.0 <= 1.2.0 is TRUE - should be included
      # 1.9.0 > 1.2.0 is TRUE - should be excluded
      # 1.10.0 > 1.2.0 is TRUE - should be excluded
      # 2.0.0 > 1.2.0 is TRUE - should be excluded
      assert device_1_1.id in device_ids, "Device 1.1.0 should be included (1.1.0 <= 1.2.0)"
      refute device_1_9.id in device_ids, "Device 1.9.0 should be excluded (1.9.0 > 1.2.0)"
      refute device_1_10.id in device_ids, "Device 1.10.0 should be excluded (1.10.0 > 1.2.0)"
      refute device_2_0.id in device_ids, "Device 2.0.0 should be excluded (2.0.0 > 1.2.0)"
    end
  end
end
