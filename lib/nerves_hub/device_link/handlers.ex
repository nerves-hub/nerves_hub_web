defmodule NervesHub.DeviceLink.Handlers do
  @moduledoc """
  Which nodes carry the platform stack — the database, the contexts, the
  extensions — and can therefore service a call that needs it.

  A node joins by starting this process, which it does when it carries that
  stack: `web` and `all` nodes join, `device` nodes start the scope without
  joining. Membership is tracked by `:pg`, so it follows nodes joining and
  leaving the cluster without anything polling or asking each node what it is.

  Ordering is deterministic on a routing key, which matters more than it looks.
  Some per-device state is node-local and not shared — the log line rate limiter
  is a token bucket in local atomics — so a device whose calls scatter across
  nodes gets a limit N times looser than configured. Sending a device's calls to
  the same node keeps that honest, and gives its queries somewhere warm to land.

  Rehashing when membership changes costs nothing here, because no state lives
  on a handler between calls.

  ## Reading this group

  `NervesHub.DeviceLink.Dispatcher.Remote` is one reader and the one this module
  is named after, but it is not the only one — `NervesHub.CLISessionCache` uses
  it to find a node that actually holds the table it wants. Anything that needs
  somewhere to send a call should ask here rather than filter `Node.list/0`: a
  node can join the topology without carrying the platform stack, and a call
  sent to one of those fails in a way that reads as an outage.

  That makes `@scope` and `@group` closer to a published contract than a private
  detail, including for anything outside this application that joins the same
  topology. They are derived from the module name, so renaming this module
  silently renames the scope, splitting membership between old and new nodes for
  the length of a rolling deploy. Pin the atoms first if it is ever moved.

  A node connected as *hidden* cannot read the group locally at all: `:pg`
  discovers its peers through `net_kernel:monitor_nodes/1` and `nodes/0`, both of
  which are visible-only. Such a node has to read membership over `:erpc` from a
  node that is in the scope.
  """

  use GenServer

  @scope __MODULE__.PG
  @group :handlers

  @doc """
  The `:pg` scope, started on every node so membership can be read.

  Part of the contract described above — see the moduledoc before changing it.
  """
  @spec scope() :: __MODULE__.PG
  def scope(), do: @scope

  @doc "Child spec for the scope itself. Every node needs this; only handlers join."
  @spec scope_spec() :: Supervisor.child_spec()
  def scope_spec(), do: %{id: @scope, start: {:pg, :start_link, [@scope]}}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Platform nodes, sorted so every node orders them the same way.

  Includes the local node when it is one.
  """
  @spec nodes() :: [node()]
  def nodes() do
    @scope
    |> :pg.get_members(@group)
    |> Enum.map(&node/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Handler nodes, rotated so the one `route_key` maps to comes first.

  The rest follow in ring order, which is what a retry walks. A `nil` key picks
  a starting point arbitrarily — appropriate only where nothing about the call
  is per-device.
  """
  @spec ordered(route_key :: term()) :: [node()]
  def ordered(route_key) do
    case nodes() do
      [] ->
        []

      nodes ->
        count = length(nodes)
        start = :erlang.phash2(route_key || make_ref(), count)

        Enum.drop(nodes, start) ++ Enum.take(nodes, start)
    end
  end

  @impl GenServer
  def init(_opts) do
    :ok = :pg.join(@scope, @group, self())
    {:ok, %{}}
  end
end
