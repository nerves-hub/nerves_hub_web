defmodule NervesHub.Products.PubSubTest do
  use ExUnit.Case, async: true

  alias NervesHub.Products.PubSub
  alias Phoenix.Socket.Broadcast

  # Unique per test so concurrent tests don't share a Group key.
  setup do
    %{product_id: System.unique_integer([:positive])}
  end

  test "broadcast_from delivers to a subscriber", %{product_id: product_id} do
    parent = self()

    sub =
      spawn(fn ->
        :ok = PubSub.subscribe(product_id)
        send(parent, :subscribed)

        receive do
          %Broadcast{} = b -> send(parent, {:got, b})
        end
      end)

    assert_receive :subscribed, 500

    :ok = PubSub.broadcast_from(product_id, "firmware/created", %{firmware: :fw})

    topic = "product:#{product_id}"
    assert_receive {:got, %Broadcast{topic: ^topic, event: "firmware/created", payload: %{firmware: :fw}}}, 500

    _ = sub
  end

  test "broadcast_from excludes the caller", %{product_id: product_id} do
    # The publisher (e.g. the Firmware LiveView) is itself subscribed; it must
    # not receive its own event, which it already handled directly.
    :ok = PubSub.subscribe(product_id)

    :ok = PubSub.broadcast_from(product_id, "firmware/created", %{firmware: :fw})

    refute_receive %Broadcast{event: "firmware/created"}, 200
  end

  test "broadcast_from reaches other subscribers while excluding the caller", %{product_id: product_id} do
    parent = self()

    other =
      spawn(fn ->
        :ok = PubSub.subscribe(product_id)
        send(parent, :subscribed)

        receive do
          %Broadcast{} = b -> send(parent, {:got, b})
        end
      end)

    assert_receive :subscribed, 500

    # Caller is also a subscriber.
    :ok = PubSub.subscribe(product_id)

    :ok = PubSub.broadcast_from(product_id, "firmware/deleted", %{firmware: :fw})

    assert_receive {:got, %Broadcast{event: "firmware/deleted"}}, 500
    refute_receive %Broadcast{event: "firmware/deleted"}, 200

    _ = other
  end
end
