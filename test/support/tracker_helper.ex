defmodule TrackerHelper do
  defmacro subscribe_for_updates(device) do
    quote do
      Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{unquote(device).identifier}:internal")
    end
  end

  defmacro assert_connection_change() do
    quote do
      assert_receive %{event: "connection:change"}
    end
  end

  defmacro refute_online(device) do
    quote do
      Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{unquote(device).identifier}:internal")
      NervesHub.Tracker.online?(unquote(device))
      refute_receive %{event: "connection:status"}
    end
  end
end
