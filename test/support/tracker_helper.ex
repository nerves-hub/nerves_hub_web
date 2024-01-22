defmodule TrackerHelper do
  defmacro assert_online(device) do
    quote do
      Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{unquote(device).identifier}:internal")
      NervesHub.Tracker.online?(unquote(device))
      assert_receive %{event: "connection_change"}
    end
  end

  defmacro refute_online(device) do
    quote do
      Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{unquote(device).identifier}:internal")
      NervesHub.Tracker.online?(unquote(device))
      refute_receive %{event: "connection_change"}
    end
  end
end
