defmodule NervesHub.ScriptRunners.PubSub do
  @moduledoc """
  Targeted pub/sub for a script run's progress, backed by the `:group` library.

  This replaces the `Phoenix.PubSub` broadcast on the `"script_runner:<id>"`
  topic. `Phoenix.PubSub`'s `pg` adapter sends every message to the pub/sub server
  on every node in the cluster, which then filters by local subscription — the
  send does not depend on anyone having subscribed. A run's only subscriber is the
  one Show LiveView somebody has open, usually none, while the traffic is one
  message per device and a run can be tens of thousands of devices wide. That is
  the shape `docs/cross_node_messaging.md` asks to be put on `:group`: sparse
  membership, dense traffic. `Group.dispatch/3` delivers only to nodes holding a
  joined member, so a run nobody is watching costs no cross-node traffic at all.

  Membership is a LiveView that is open, so it does not churn with the fleet the
  way device connections do, and joins are paid once per page view rather than per
  device event.

  Messages keep the shape they had under `Phoenix.PubSub` — the bare
  `{:script_runner, event, payload}` tuple rather than a
  `%Phoenix.Socket.Broadcast{}` — because the only receiver matches on the tuple
  directly. Only the subscribe/broadcast call sites move here.

  Default `:group` cluster, like the other device ↔ UI topics: the publisher is an
  Oban worker on a web node and the subscriber is a LiveView on a web node, but
  the default cluster needs no explicit `connect` and carries every other
  per-entity UI topic.
  """

  @group NervesHub.Group

  @doc """
  Join the calling process (a run's Show LiveView) to the run's progress group.

  Membership is cleaned up when the calling process dies, mirroring
  `Phoenix.PubSub` subscription behaviour.
  """
  @spec subscribe(integer()) :: :ok
  def subscribe(runner_id) do
    :ok = Group.join(@group, key(runner_id), %{})
  end

  @doc """
  Dispatch a progress event to every process joined to the run's group.

  Returns `:ok` even when nothing has joined — a run with nobody watching it is
  the common case and is not an error.
  """
  @spec broadcast(integer(), atom(), map()) :: :ok
  def broadcast(runner_id, event, payload) do
    message = {:script_runner, event, Map.put(payload, :script_runner_id, runner_id)}

    Group.dispatch(@group, key(runner_id), message)
  end

  # Group key. "/" is Group's hierarchy separator, which keeps the door open for
  # future prefix queries.
  defp key(runner_id), do: "script_runner/#{runner_id}"
end
