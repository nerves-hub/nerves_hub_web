defmodule NervesHub.Devices.Distributed.OrchestratorTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Deployments.Distributed.Monitor
  alias NervesHub.Deployments.Distributed.Orchestrator

  alias NervesHub.Deployments
  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Fixtures

  alias Phoenix.Socket.Broadcast

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    deployment = Fixtures.deployment_fixture(org, firmware, %{is_active: true})
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
       deployment: deployment,
       product: product
     }}
  end

  test "the concurrent_limit is respected", %{
    product: product,
    deployment: deployment,
    org_key: org_key,
    device: device1,
    device2: device2,
    device3: device3
  } do
    Application.put_env(:nerves_hub, :deployments_orchestrator, "clustered")

    on_exit(fn ->
      Application.put_env(:nerves_hub, :deployments_orchestrator, "multi")
    end)

    # setup deployment, listen for broadcasts, and start the orchestrator
    firmware = Fixtures.firmware_fixture(org_key, product)

    {:ok, deployment} =
      Deployments.update_deployment(deployment, %{concurrent_updates: 2, firmware_id: firmware.id})

    deployment_topic = "deployment:#{deployment.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, deployment_topic)

    {:ok, _pid} =
      start_supervised(%{
        id: "Orchestrator##{deployment.id}",
        start: {Orchestrator, :start_link_for_testing, [deployment]},
        restart: :temporary
      })

    # assign a device to the deployment and mark it as 'connected'
    topic1 = "device:#{device1.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, topic1)

    device1 = Devices.update_deployment(device1, deployment)
    Connections.device_connected(device1.id)
    Devices.deployment_device_online(device1)

    # check that the first device was told to update
    assert_receive %Broadcast{topic: ^topic1, event: "update-scheduled"}, 500

    # assign a second device to the deployment and mark it as connected
    topic2 = "device:#{device2.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, topic2)

    device2 = Devices.update_deployment(device2, deployment)
    Connections.device_connected(device2.id)
    Devices.deployment_device_online(device2)

    # and check that device2 was told to update
    assert_receive %Broadcast{topic: ^topic2, event: "update-scheduled"}, 500

    # and now assign a third device to the deployment and mark it as connected
    topic3 = "device:#{device3.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, topic3)

    device3 = Devices.update_deployment(device3, deployment)
    Connections.device_connected(device3.id)
    Devices.deployment_device_online(device3)

    # and check that device3 isn't told to update as the concurrent limit has been reached
    refute_receive %Broadcast{topic: ^topic3, event: "update-scheduled"}, 500
  end

  test "finds another device to update when a device finishes updating", %{
    product: product,
    deployment: deployment,
    org_key: org_key,
    device: device,
    device2: device2
  } do
    Application.put_env(:nerves_hub, :deployments_orchestrator, "clustered")

    on_exit(fn ->
      Application.put_env(:nerves_hub, :deployments_orchestrator, "multi")
    end)

    # only allow for 1 update at a time
    {:ok, deployment} = Deployments.update_deployment(deployment, %{concurrent_updates: 1})

    device = Devices.update_deployment(device, deployment)
    Connections.device_connected(device.id)

    device2 = Devices.update_deployment(device2, deployment)
    Connections.device_connected(device2.id)

    topic1 = "device:#{device.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, topic1)

    topic2 = "device:#{device2.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, topic2)

    deployment_topic = "deployment:#{deployment.id}"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, deployment_topic)

    {:ok, _pid} =
      start_supervised(%{
        id: "Orchestrator##{deployment.id}",
        start: {Orchestrator, :start_link_for_testing, [deployment]},
        restart: :temporary
      })

    # create new firmware and update the deployment with it
    firmware = Fixtures.firmware_fixture(org_key, product)

    {:ok, _deployment} = Deployments.update_deployment(deployment, %{firmware_id: firmware.id})

    # check that the first device was told to update
    assert_receive %Broadcast{topic: ^topic1, event: "update-scheduled"}, 500

    # bring the second device 'online'
    Devices.update_deployment(device2, deployment)
    Connections.device_connected(device2.id)

    # pretend that the first device successfully updated
    {:ok, device} =
      Devices.update_device(device, %{firmware_metadata: %{"uuid" => firmware.uuid}})

    Devices.firmware_update_successful(device)

    # check that the orchestractor was told about the successful update
    assert_receive %Broadcast{topic: ^deployment_topic, event: "deployment/device-updated"}, 500

    # and that device2 was told to update
    assert_receive %Broadcast{topic: ^topic2, event: "update-scheduled"}, 500
  end

  test "shuts down if the deployment is no longer active", %{deployment: deployment} do
    {:ok, pid} =
      start_supervised(%{
        id: "Orchestrator##{deployment.id}",
        start: {Orchestrator, :start_link_for_testing, [deployment]},
        restart: :temporary
      })

    Process.monitor(pid)

    Monitor.stop_orchestrator(deployment)

    assert_receive {:DOWN, _reference, :process, ^pid, :shutdown}, 500
  end

  test "shuts down if the deployment deleted", %{deployment: deployment} do
    Application.put_env(:nerves_hub, :deployments_orchestrator, "clustered")

    on_exit(fn ->
      Application.put_env(:nerves_hub, :deployments_orchestrator, "multi")
    end)

    {:ok, pid} =
      start_supervised(%{
        id: "Orchestrator##{deployment.id}",
        start: {Orchestrator, :start_link_for_testing, [deployment]},
        restart: :temporary
      })

    Process.monitor(pid)

    Deployments.delete_deployment(deployment)

    assert_receive {:DOWN, _reference, :process, ^pid, :shutdown}, 3_000
  end
end
