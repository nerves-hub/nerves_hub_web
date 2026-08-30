defmodule NervesHub.Extensions.PubSubTest do
  use ExUnit.Case, async: true

  alias NervesHub.Extensions.PubSub
  alias Phoenix.Socket.Broadcast

  # Unique per test so concurrent tests don't share a group key or topic.
  setup do
    %{device_id: System.unique_integer([:positive])}
  end

  test "broadcast_to_device reaches the device-side extensions channel", %{
    device_id: device_id
  } do
    :ok = PubSub.subscribe_device(device_id)

    :ok = PubSub.broadcast_to_device(device_id, "health:check", %{})

    topic = "device:#{device_id}:extensions"
    assert_receive %Broadcast{topic: ^topic, event: "health:check", payload: %{}}, 500
  end

  test "broadcast_report reaches a report subscriber (the Show LiveView)", %{device_id: device_id} do
    :ok = PubSub.subscribe_reports(device_id)

    :ok = PubSub.broadcast_report(device_id, "health_check_report", %{})

    assert_receive %Broadcast{event: "health_check_report"}, 500
  end

  test "a report is NOT echoed to the device-side channel (self-exclusion via direction split)", %{
    device_id: device_id
  } do
    # The device-side channel subscribes to the web->device topic only.
    :ok = PubSub.subscribe_device(device_id)

    :ok = PubSub.broadcast_report(device_id, "health_check_report", %{})

    # It must not receive the report it (in production) originated — otherwise it
    # would push it straight back down to the device.
    refute_receive %Broadcast{event: "health_check_report"}, 200
  end

  test "a report subscriber does NOT receive web->device commands", %{
    device_id: device_id
  } do
    :ok = PubSub.subscribe_reports(device_id)

    :ok = PubSub.broadcast_to_device(device_id, "health:check", %{})

    refute_receive %Broadcast{event: "health:check"}, 200
  end

  test "the device-side subscription is node-local, so it is not a group member", %{
    device_id: device_id
  } do
    # The whole point of keeping web->device on Phoenix.PubSub: a connected
    # device must not put a cluster-replicated membership row on every node.
    :ok = PubSub.subscribe_device(device_id)

    assert Group.members(NervesHub.Group, "device:extensions/#{device_id}") == []
  end

  describe "product-wide events (Phoenix.PubSub)" do
    setup do
      %{product_id: System.unique_integer([:positive])}
    end

    test "broadcast_to_product reaches a subscribed device", %{product_id: product_id} do
      :ok = PubSub.subscribe_product(product_id)

      # broadcast_from! excludes the caller, so publish from another process.
      task = Task.async(fn -> PubSub.broadcast_to_product(product_id, "attach", %{"extensions" => ["health"]}) end)
      Task.await(task)

      topic = "product:#{product_id}:extensions"
      assert_receive %Broadcast{topic: ^topic, event: "attach", payload: %{"extensions" => ["health"]}}, 500
    end

    test "broadcast_to_product excludes the caller (self-exclusion preserved)", %{product_id: product_id} do
      :ok = PubSub.subscribe_product(product_id)

      :ok = PubSub.broadcast_to_product(product_id, "detach", %{"extensions" => ["health"]})

      refute_receive %Broadcast{event: "detach"}, 200
    end
  end
end
