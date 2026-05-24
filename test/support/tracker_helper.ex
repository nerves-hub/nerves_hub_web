defmodule TrackerHelper do
  @moduledoc false

  defmacro subscribe_for_updates(device) do
    quote do
      Phoenix.PubSub.subscribe(NervesHub.PubSub, "internal:device:#{unquote(device).id}")
    end
  end

  defmacro assert_connection_change() do
    quote do
      assert_receive %{event: "connection:change"}
    end
  end

  defmacro refute_online(device) do
    quote do
      Phoenix.PubSub.subscribe(NervesHub.PubSub, "internal:device:#{unquote(device).id}")
      NervesHub.Tracker.online?(unquote(device))
      refute_receive %{event: "connection:change"}
    end
  end
end
