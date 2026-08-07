defmodule NervesHub.Extensions.PubSubTest do
  use ExUnit.Case, async: true

  alias NervesHub.Extensions.PubSub
  alias Phoenix.Socket.Broadcast

  # Unique per test so concurrent tests don't share a Group key.
  setup do
    %{device_id: System.unique_integer([:positive])}
  end

  test "broadcast_to_device reaches the device-side extensions channel", %{device_id: device_id} do
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

  test "a report is NOT echoed to the device-side channel (self-exclusion via key split)", %{
    device_id: device_id
  } do
    # The device-side channel joins the web->device key only.
    :ok = PubSub.subscribe_device(device_id)

    :ok = PubSub.broadcast_report(device_id, "health_check_report", %{})

    # It must not receive the report it (in production) originated — otherwise it
    # would push it straight back down to the device.
    refute_receive %Broadcast{event: "health_check_report"}, 200
  end

  test "a report subscriber does NOT receive web->device commands", %{device_id: device_id} do
    :ok = PubSub.subscribe_reports(device_id)

    :ok = PubSub.broadcast_to_device(device_id, "health:check", %{})

    refute_receive %Broadcast{event: "health:check"}, 200
  end
end
