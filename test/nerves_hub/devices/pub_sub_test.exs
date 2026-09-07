defmodule NervesHub.Devices.PubSubTest do
  use ExUnit.Case, async: true

  alias NervesHub.Devices.PubSub
  alias Phoenix.Socket.Broadcast

  # Unique per test so concurrent tests don't share a Group key.
  setup do
    %{device_id: System.unique_integer([:positive])}
  end

  test "a joined process receives dispatched events as a %Broadcast{}", %{device_id: device_id} do
    :ok = PubSub.subscribe(device_id)
    :ok = PubSub.broadcast(device_id, "connection:change", %{status: "online"})

    topic = "internal:device:#{device_id}"

    assert_receive %Broadcast{
                     topic: ^topic,
                     event: "connection:change",
                     payload: %{status: "online"}
                   },
                   500
  end

  test "a process that never joined receives nothing", %{device_id: device_id} do
    :ok = PubSub.broadcast(device_id, "connection:change", %{status: "online"})

    refute_receive %Broadcast{}, 200
  end

  test "unsubscribe stops delivery", %{device_id: device_id} do
    :ok = PubSub.subscribe(device_id)
    :ok = PubSub.unsubscribe(device_id)

    :ok = PubSub.broadcast(device_id, "connection:change", %{status: "online"})

    refute_receive %Broadcast{}, 200
  end

  test "unsubscribing without having subscribed is not an error", %{device_id: device_id} do
    # The devices index leaves keys in bulk as the visible page changes and does
    # not track which it actually holds, so this has to be idempotent.
    assert :ok = PubSub.unsubscribe(device_id)

    :ok = PubSub.subscribe(device_id)
    assert :ok = PubSub.unsubscribe(device_id)
    assert :ok = PubSub.unsubscribe(device_id)
  end
end
