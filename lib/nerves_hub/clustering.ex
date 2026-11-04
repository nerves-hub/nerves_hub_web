defmodule NervesHub.Clustering do
  @moduledoc """
  How this node finds the other nodes in its cluster: the libcluster topologies
  that `NervesHub.Application` starts.

  `CLUSTER_STRATEGY` picks the strategies (see "Clustering" in
  `docs/runtime_configuration.md`):

    * `postgres`, the default. Every node announces its name on the Postgres
      channel `nerves_hub_clustering` and connects to the names it hears. It
      works wherever the database is reachable, with nothing else to set up.
      Nodes with different basenames find each other, since each one announces
      its full name. Another application joins by listening on the same channel.
    * `dns`. Looks up each name in `DNS_CLUSTER_QUERY` and connects to
      `basename@address` for every address it resolves to. This suits platforms
      that keep a name resolving to every node, such as a Kubernetes headless
      Service or Fly.io's `<app>.internal`. An entry with no basename uses this
      node's own.

      Names are looked up exactly as given, without the search domains in
      `/etc/resolv.conf`, so a Kubernetes Service needs its full name. That is
      libcluster's resolver. `:inet_res.getbyname/2` would apply the search
      domains, but it answers from a cache for as long as the record's TTL
      (600 seconds from Docker's DNS), so a node that starts in the meantime
      goes unseen by anything that relies on polling to find it.

  Both can run at once. That is how a cluster moves from one to the other
  without any node losing sight of the rest.

  Neither strategy disconnects a node because discovery has stopped seeing it.
  A node leaves when it stops, or when Erlang distribution loses the connection.
  A node that is shutting down still has work to do over distribution: handing
  deployment orchestrators over to another node, or serving devices while it
  drains their sockets. By default, Kubernetes drops a terminating pod from its
  Service's DNS answers straight away, before that work is done.
  """

  alias Cluster.Strategy.DNSPoll

  require Logger

  @channel_name "nerves_hub_clustering"

  @typedoc "One `DNS_CLUSTER_QUERY` entry: the basename to connect to, or `nil` for this node's own, and the name to look up."
  @type dns_query() :: {basename :: String.t() | nil, hostname :: String.t()}

  @doc """
  The libcluster topologies for this node, from the `:nerves_hub, NervesHub.Clustering`
  config that `config/runtime.exs` sets.
  """
  @spec topologies() :: keyword()
  def topologies() do
    topologies(Application.get_env(:nerves_hub, __MODULE__, []), NervesHub.Repo.config(), node())
  end

  @doc """
  The libcluster topologies for `config`, given the repo config the Postgres
  strategy connects with and the name of this node.

  `config` takes `:strategies`, a list of `:postgres` and `:dns` (default
  `[:postgres]`), and `:dns_queries`, a list of `t:dns_query/0`.
  """
  @spec topologies(keyword(), keyword(), node()) :: keyword()
  def topologies(config, repo_config, node) do
    config
    |> Keyword.get(:strategies, [:postgres])
    |> Enum.flat_map(fn
      :postgres -> [postgres: postgres_topology(repo_config)]
      :dns -> dns_topologies(Keyword.get(config, :dns_queries, []), node)
    end)
  end

  defp postgres_topology(repo_config) do
    config =
      repo_config
      |> Keyword.take([:hostname, :username, :password, :database, :port, :ssl])
      |> Keyword.put(:parameters, [])
      |> Keyword.put(:channel_name, @channel_name)

    [strategy: LibclusterPostgres.Strategy, config: config]
  end

  # A node that isn't distributed can't connect to anything, and has no
  # basename of its own to offer an entry without one.
  defp dns_topologies(_dns_queries, :nonode@nohost) do
    Logger.warning("CLUSTER_STRATEGY includes dns, but this node isn't distributed, so it won't join a cluster")

    []
  end

  defp dns_topologies(dns_queries, node) do
    [own_basename, _host] = node |> Atom.to_string() |> String.split("@", parts: 2)

    for {basename, hostname} <- dns_queries do
      basename = basename || own_basename

      topology = [
        strategy: DNSPoll,
        config: [query: hostname, node_basename: basename, prune: false]
      ]

      {:"dns:#{basename}@#{hostname}", topology}
    end
  end
end
