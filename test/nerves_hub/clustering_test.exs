defmodule NervesHub.ClusteringTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Cluster.Strategy.DNSPoll
  alias NervesHub.Clustering

  @repo_config [
    hostname: "db.internal",
    username: "nerves_hub",
    password: "secret",
    database: "nerves_hub",
    port: 5432,
    ssl: false,
    pool_size: 20,
    url: "postgres://nerves_hub:secret@db.internal/nerves_hub"
  ]

  @node :"nerves-hub-web@10.0.0.1"

  describe "topologies/3" do
    test "uses Postgres alone by default, on the channel the other applications listen on" do
      assert [postgres: [strategy: LibclusterPostgres.Strategy, config: config]] =
               Clustering.topologies([], @repo_config, @node)

      assert config[:channel_name] == "nerves_hub_clustering"
      assert config[:hostname] == "db.internal"
      assert config[:parameters] == []

      # Only what a connection needs, not the repo's pool and URL.
      refute Keyword.has_key?(config, :pool_size)
      refute Keyword.has_key?(config, :url)
    end

    test "polls each DNS name, with this node's basename unless the entry names another" do
      config = [
        strategies: [:dns],
        dns_queries: [{nil, "nerves-hub-web-cluster"}, {"nerves-hub-device", "nerves-hub-device-cluster"}]
      ]

      assert [
               {:"dns:nerves-hub-web@nerves-hub-web-cluster", web},
               {:"dns:nerves-hub-device@nerves-hub-device-cluster", device}
             ] = Clustering.topologies(config, @repo_config, @node)

      assert web[:strategy] == DNSPoll
      assert web[:config][:query] == "nerves-hub-web-cluster"
      assert web[:config][:node_basename] == "nerves-hub-web"

      assert device[:config][:query] == "nerves-hub-device-cluster"
      assert device[:config][:node_basename] == "nerves-hub-device"
    end

    test "never disconnects a node because DNS stopped answering for it" do
      config = [strategies: [:dns], dns_queries: [{nil, "nerves-hub-web-cluster"}]]

      for {_name, topology} <- Clustering.topologies(config, @repo_config, @node) do
        assert topology[:config][:prune] == false
      end
    end

    # A resolver built on :inet_res.getbyname/2 answers from a cache for the
    # record's TTL, so nodes started since the last real lookup go unseen.
    test "uses libcluster's resolver, which asks DNS on every poll" do
      config = [strategies: [:dns], dns_queries: [{nil, "nerves-hub-web-cluster"}]]

      for {_name, topology} <- Clustering.topologies(config, @repo_config, @node) do
        refute Keyword.has_key?(topology[:config], :resolver)
      end
    end

    test "runs Postgres and DNS together, for moving from one to the other" do
      config = [strategies: [:postgres, :dns], dns_queries: [{nil, "nerves-hub-web-cluster"}]]

      assert [:postgres, :"dns:nerves-hub-web@nerves-hub-web-cluster"] =
               config |> Clustering.topologies(@repo_config, @node) |> Keyword.keys()
    end

    test "starts no DNS discovery on a node that isn't distributed" do
      config = [strategies: [:dns], dns_queries: [{nil, "nerves-hub-web-cluster"}]]

      log =
        capture_log(fn ->
          assert Clustering.topologies(config, @repo_config, :nonode@nohost) == []
        end)

      assert log =~ "isn't distributed"
    end
  end
end
