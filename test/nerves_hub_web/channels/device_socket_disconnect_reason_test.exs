defmodule NervesHubWeb.DeviceSocketDisconnectReasonTest do
  # `terminate/2` hears `:normal` from Bandit for a "disconnect" broadcast and
  # a drain alike, so the socket notes why on the way in. These call
  # `handle_info/2` directly, since neither can be told apart from outside.
  use ExUnit.Case, async: true

  alias NervesHub.DeviceEvents
  alias NervesHubWeb.DeviceSocket
  alias Phoenix.Socket
  alias Phoenix.Socket.Broadcast

  defp handle(message) do
    {:stop, stop_reason, {_state, socket}} = DeviceSocket.handle_info(message, {%{}, %Socket{}})
    {stop_reason, socket.assigns[:disconnect_reason]}
  end

  test "a disconnect broadcast that says why" do
    assert {{:shutdown, :disconnected}, :reconnect_requested} =
             handle(%Broadcast{event: "disconnect", payload: %{reason: "reconnect_requested"}})

    assert {{:shutdown, :disconnected}, :key_revoked} =
             handle(%Broadcast{event: "disconnect", payload: %{reason: "key_revoked"}})
  end

  # As older nodes send it, and as `DeviceEvents.deleted/1` still does.
  test "a disconnect broadcast with no reason, or one this release does not know" do
    assert {{:shutdown, :disconnected}, nil} = handle(%Broadcast{event: "disconnect", payload: %{}})

    assert {{:shutdown, :disconnected}, nil} =
             handle(%Broadcast{event: "disconnect", payload: %{reason: "a reason from the future"}})
  end

  test "a drain is a platform update" do
    assert {{:shutdown, :restart}, :platform_update} = handle(:socket_drain)
  end

  test "DeviceEvents.reconnect/1 says why" do
    device_id = System.unique_integer([:positive])
    :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, "device_socket:#{device_id}")

    :ok = DeviceEvents.reconnect(%{id: device_id})

    assert_receive %Broadcast{event: "disconnect", payload: %{reason: "reconnect_requested"}}
  end
end
