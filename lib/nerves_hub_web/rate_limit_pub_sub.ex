defmodule NervesHubWeb.RateLimitPubSub do
  @moduledoc """
  Keeps PlugAttack IP-throttle counts in sync across web nodes.

  Only the web endpoint runs the throttle (it guards the `check_cli_session` API
  action), so this is scoped to the named "web" Group cluster — device nodes
  neither run this process nor carry its membership. The originating node has
  already applied the increment inline in `Attack.ip_throttle/1`; dispatching to
  the group tells the *other* web nodes to apply the same increment, so their
  local ETS agrees and the per-IP limit is enforced cluster-wide rather than
  per-node.
  """

  use GenServer

  alias NervesHubWeb.Plugs.Attack

  @cluster "web"
  @group "ratelimit"

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def broadcast(key, time) do
    # `Group.dispatch/4` has no self-exclusion, so stamp the origin node and skip
    # it on receipt — it already incremented inline in `Attack.ip_throttle/1`.
    Group.dispatch(NervesHub.Group, @group, {:throttle, key, time, node()}, cluster: @cluster)
  end

  @impl GenServer
  def init([]) do
    :ok = Group.join(NervesHub.Group, @group, %{}, cluster: @cluster)
    {:ok, []}
  end

  @impl GenServer
  def handle_info({:throttle, _key, _time, origin}, state) when origin == node() do
    # Our own dispatch echoed back; the increment already happened inline.
    {:noreply, state}
  end

  def handle_info({:throttle, {:ip, ip}, time, _origin}, state) do
    _ = Attack.ip_throttle(ip, time: time)
    {:noreply, state}
  end
end
