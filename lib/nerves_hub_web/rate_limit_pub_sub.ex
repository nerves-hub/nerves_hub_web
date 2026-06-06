defmodule NervesHubWeb.RateLimitPubSub do
  use GenServer

  alias NervesHubWeb.Plugs.Attack

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def broadcast(key, time) do
    server = GenServer.whereis(__MODULE__)
    Phoenix.PubSub.broadcast_from!(NervesHub.PubSub, server, "ratelimit", {:throttle, key, time})
  end

  def init([]) do
    _ = Phoenix.PubSub.subscribe(NervesHub.PubSub, "ratelimit")
    {:ok, []}
  end

  def handle_info({:throttle, {:ip, ip}, time}, []) do
    _ = Attack.ip_throttle(ip, time: time)
    {:noreply, []}
  end
end
