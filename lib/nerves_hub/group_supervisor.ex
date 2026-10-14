defmodule NervesHub.GroupSupervisor do
  @moduledoc """
  Supervises `:group` together with everything whose state does not outlive it.

  `Group` keeps cluster membership, group memberships and monitors in ETS owned
  by its own supervision tree. If that tree restarts, the state is rebuilt
  empty, and nothing below notices:

    * `NervesHub.GroupClusterConnection` connects to the named "web" cluster
      once, from `init/1`. After a `Group` restart the local node is no longer a
      member of "web", and the next `Group.join/4` against it raises
      `ArgumentError` from the library's connected-cluster check.
    * `NervesHub.CLISessionCache` and `NervesHubWeb.RateLimitPubSub` join their
      "web" groups from `init/1` too. After a restart they are silently no
      longer members: `Group.dispatch/4` does not validate the cluster, so their
      writes stop reaching peers without erroring.

  Under the application's `:one_for_one` strategy none of that would be
  repaired. `:rest_for_one` ties them together in dependency order, so a `Group`
  restart restarts the connection and both members and each re-runs `init/1`
  against the fresh tree.

  Both members are gated off device nodes, which never connect to "web".
  """

  use Supervisor

  # Group keeps every local join and leave in a per-shard replica oplog so a
  # lagging peer can catch up from deltas. It is pruned by count alone, so the
  # default (65,536 per shard) fills to about 300 MiB of ETS per node under
  # ordinary churn and stays there, members or not. Our memberships are UI-sized,
  # so a peer that falls further behind than this gets an exact snapshot of a
  # few hundred rows instead. 1,024 per shard holds about 5 MiB.
  @oplog_max_entries 1_024

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl Supervisor
  def init(_) do
    children =
      [
        {Group, name: NervesHub.Group, replicated_oplog_max_entries: @oplog_max_entries},
        NervesHub.GroupClusterConnection
      ] ++ web_cluster_members()

    Supervisor.init(children, strategy: :rest_for_one)
  end

  # Only web/all nodes serve the throttled `check_cli_session` endpoint and the
  # CLI session cache, and only they connect to the "web" cluster these join.
  defp web_cluster_members() do
    case Application.get_env(:nerves_hub, :app) do
      "device" -> []
      _ -> [NervesHub.CLISessionCache, NervesHubWeb.RateLimitPubSub]
    end
  end
end
