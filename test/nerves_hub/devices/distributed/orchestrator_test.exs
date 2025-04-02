defmodule NervesHub.Devices.Distributed.OrchestratorTest do
  use NervesHub.DataCase, async: false

  use Mimic

  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Distributed.Orchestrator

  alias Phoenix.Socket.Broadcast

  setup :set_mimic_global

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)

    stub(Orchestrator, :start_orchestrator, fn _deployment ->
      :ok
    end)

    deployment_group = Fixtures.deployment_group_fixture(org, firmware, %{is_active: true})

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
    device3: device3
  } do
    # setup deployment group, listen for broadcasts, and start the orchestrator
    firmware = Fixtures.firmware_fixture(org_key, product)

    {:ok, deployment_group} =
      ManagedDeployments.update_deployment_group(deployment_group, %{
        concurrent_updates: 2,
        firmware_id: firmware.id
      })

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
    {:ok, connection} = Connections.device_connecting(device1.id, device1.product_id)
    :ok = Connections.device_connected(connection.id)
    Devices.deployment_device_online(device1)

    # sent when a device is a assigned a deployment group
    assert_receive %Broadcast{topic: ^topic1, event: "devices/deployment-updated"}, 500

    # check that the first device was told to update
    assert_receive %Broadcast{topic: ^topic1, event: "update-scheduled"}, 500

    # assign a second device to the deployment group and mark it as connected
    topic2 = "device:#{device2.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, topic2)

    device2 = Devices.update_deployment_group(device2, deployment_group)
    {:ok, connection} = Connections.device_connecting(device2.id, device2.product_id)
    :ok = Connections.device_connected(connection.id)
    Devices.deployment_device_online(device2)

    # and check that device2 was told to update
    assert_receive %Broadcast{topic: ^topic2, event: "update-scheduled"}, 500

    # and now assign a third device to the deployment group and mark it as connected
    topic3 = "device:#{device3.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, topic3)

    device3 = Devices.update_deployment_group(device3, deployment_group)
    {:ok, connection} = Connections.device_connecting(device3.id, device3.product_id)
    :ok = Connections.device_connected(connection.id)
    Devices.deployment_device_online(device3)

    # and check that device3 isn't told to update as the concurrent limit has been reached
    refute_receive %Broadcast{topic: ^topic3, event: "update-scheduled"}, 500
  end

  test "finds another device to update when a device finishes updating", %{
    product: product,
    deployment_group: deployment_group,
    org_key: org_key,
    device: device,
    device2: device2
  } do
    # only allow for 1 update at a time
    {:ok, deployment_group} =
      ManagedDeployments.update_deployment_group(deployment_group, %{concurrent_updates: 1})

    device = Devices.update_deployment_group(device, deployment_group)
    {:ok, connection} = Connections.device_connecting(device.id, device.product_id)
    :ok = Connections.device_connected(connection.id)

    device2 = Devices.update_deployment_group(device2, deployment_group)
    {:ok, connection} = Connections.device_connecting(device2.id, device2.product_id)
    :ok = Connections.device_connected(connection.id)

    topic1 = "device:#{device.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, topic1)

    topic2 = "device:#{device2.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, topic2)

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
      ManagedDeployments.update_deployment_group(deployment_group, %{firmware_id: firmware.id})

    # check that the first device was told to update
    assert_receive %Broadcast{topic: ^topic1, event: "update-scheduled"}, 500

    # bring the second device 'online'
    Devices.update_deployment_group(device2, deployment_group)
    {:ok, connection} = Connections.device_connecting(device2.id, device2.product_id)
    :ok = Connections.device_connected(connection.id)

    # sent by the device after its updated
    assert_receive %Broadcast{topic: ^topic2, event: "devices/deployment-updated"}, 500

    # pretend that the first device successfully updated
    {:ok, device} =
      Devices.update_device(device, %{firmware_metadata: %{"uuid" => firmware.uuid}})

    Devices.firmware_update_successful(device)

    # sent by the device after its updated
    assert_receive %Broadcast{topic: ^topic1, event: "devices/updated"}, 500

    # check that the orchestrator was told about the successful update
    assert_receive %Broadcast{topic: ^deployment_group_topic, event: "device-updated"}, 500

    # and that device2 was told to update
    assert_receive %Broadcast{topic: ^topic2, event: "update-scheduled"}, 500
  end

  test "the orchestrator doesn't 'trigger' if the device that came online is up-to-date", %{
    deployment_group: deployment_group,
    org_key: org_key,
    product: product,
    device: device1,
    device2: device2
  } do
    # An ugly set of expectations
    # `Devices.available_for_update` should be called:
    # - once upon Orchestrator startup
    # - once for when an out of date device comes online
    # - and nooooo more times after that
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
      ManagedDeployments.update_deployment_group(deployment_group, %{
        concurrent_updates: 2,
        firmware_id: firmware.id
      })

    deployment_group_topic = "orchestrator:deployment:#{deployment_group.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, deployment_group_topic)

    {:ok, pid} =
      start_supervised(%{
        id: "Orchestrator##{deployment_group.id}",
        start: {Orchestrator, :start_link, [deployment_group, false]},
        restart: :temporary
      })

    # only one device in this test isn't using the same firmware as the deployment group
    # the `Devices.available_for_update/2` function should only be called once by device1

    # assign device1 to the deployment group and mark it as 'connected'
    # this device will be told to update
    device1_topic = "device:#{device1.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, device1_topic)

    device1 = Devices.update_deployment_group(device1, deployment_group)

    {:ok, connection} = Connections.device_connecting(device1.id, device1.product_id)
    :ok = Connections.device_connected(connection.id)

    Devices.deployment_device_online(device1)

    # sent when a device is assigned a deployment group
    assert_receive %Broadcast{topic: ^device1_topic, event: "devices/deployment-updated"},
                   500

    # the orchestrator is told that a device assigned to it is online
    assert_receive %Broadcast{topic: ^deployment_group_topic, event: "device-online"}, 500

    # and then a device is told to schedule an update
    assert_receive %Broadcast{topic: ^device1_topic, event: "update-scheduled"}, 1_000

    Mimic.reject(&Devices.available_for_update/2)

    # device2 is already on the latest firmware, so when it comes online
    # `Devices.available_for_update/2` won't be called and the device won't
    # be told to update
    device2_topic = "device:#{device2.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, device2_topic)

    {:ok, device2} =
      Devices.update_device(device2, %{firmware_metadata: %{"uuid" => firmware.uuid}})

    device2 = Devices.update_deployment_group(device2, deployment_group)
    {:ok, connection} = Connections.device_connecting(device2.id, device2.product_id)
    :ok = Connections.device_connected(connection.id)
    Devices.deployment_device_online(device2)

    assert_receive %Broadcast{topic: ^deployment_group_topic, event: "device-online"}, 500
    refute_receive %Broadcast{topic: ^device2_topic, event: "update-scheduled"}, 500

    # allows for db connections to finish and close
    _state = :sys.get_state(pid)
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
      ManagedDeployments.update_deployment_group(deployment_group, %{
        concurrent_updates: 2,
        firmware_id: firmware.id
      })

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

    {:ok, connection} = Connections.device_connecting(device1.id, device1.product_id)
    :ok = Connections.device_connected(connection.id)

    Devices.deployment_device_online(device1)

    # sent when a device is assigned a deployment group
    assert_receive %Broadcast{topic: ^device1_topic, event: "devices/deployment-updated"},
                   500

    # the orchestrator is told that a device assigned to it is online
    assert_receive %Broadcast{topic: ^deployment_topic, event: "device-online"}, 500

    # the device isn't told to update, yet
    refute_receive %Broadcast{topic: ^device1_topic, event: "update-scheduled"}, 1_000

    # we enable updates for the device
    Devices.enable_updates(device1, user)

    # and then a device is told to schedule an update
    assert_receive %Broadcast{topic: ^device1_topic, event: "update-scheduled"}, 1_000

    # allows for db connections to finish and close
    _state = :sys.get_state(pid)
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
end
