defmodule NervesHub.Firmwares.PubSubTest do
  use ExUnit.Case, async: true

  alias NervesHub.Firmwares.FirmwareDelta
  alias NervesHub.Firmwares.PubSub
  alias Phoenix.Socket.Broadcast

  # Unique per test so concurrent tests don't share a Group key.
  setup do
    target_id = System.unique_integer([:positive])

    delta = %FirmwareDelta{
      id: System.unique_integer([:positive]),
      source_id: System.unique_integer([:positive]),
      target_id: target_id,
      status: :completed
    }

    %{target_id: target_id, delta: delta}
  end

  test "a joined process receives the delta status as a %Broadcast{}", %{
    target_id: target_id,
    delta: delta
  } do
    :ok = PubSub.subscribe_delta_target(target_id)
    :ok = PubSub.broadcast_delta_status(delta)

    # The topic keeps the legacy `firmware:<id>` form even though the group key
    # is `firmware/<id>`, because the receiver matches on `"firmware:" <> _`.
    topic = "firmware:#{target_id}"
    delta_id = delta.id
    source_id = delta.source_id

    assert_receive %Broadcast{
                     topic: ^topic,
                     event: "delta/status_update",
                     payload: %{
                       delta_id: ^delta_id,
                       source_firmware_id: ^source_id,
                       status: :completed
                     }
                   },
                   500
  end

  test "a process joined to a different target receives nothing", %{delta: delta} do
    :ok = PubSub.subscribe_delta_target(System.unique_integer([:positive]))
    :ok = PubSub.broadcast_delta_status(delta)

    refute_receive %Broadcast{}, 200
  end

  test "unsubscribe stops delivery", %{target_id: target_id, delta: delta} do
    :ok = PubSub.subscribe_delta_target(target_id)
    :ok = PubSub.unsubscribe_delta_target(target_id)

    :ok = PubSub.broadcast_delta_status(delta)

    refute_receive %Broadcast{}, 200
  end

  test "unsubscribing from a target that was never joined is not an error", %{
    target_id: target_id
  } do
    assert :ok == PubSub.unsubscribe_delta_target(target_id)
  end
end
