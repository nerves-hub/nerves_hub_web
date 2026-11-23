defmodule NervesHub.CLISessionCacheClusterTest do
  @moduledoc """
  CLI logins across two web nodes.

  A peer node stands in for a second web node: it runs `NervesHub.Group`, joins
  the "web" cluster and starts a `NervesHub.CLISessionCache` of its own, so a
  login can be owned by either node. It has no database, so a login is only
  confirmed here when this node owns it.
  """

  # Not async: the owner's cache mints API tokens in its own process, which only
  # reaches the database through the shared sandbox. And this starts
  # distribution, which the whole node shares.
  use NervesHub.DataCase, async: false

  alias NervesHub.Accounts
  alias NervesHub.Accounts.UserCLISession
  alias NervesHub.CLISessionCache
  alias NervesHub.Fixtures

  # Compiled on both nodes, since the peer can't load a module defined in this
  # file.
  @probe """
  defmodule CLISessionCacheProbe do
    def where(_current), do: {node(), :noop}
    def store(_current, cli_session), do: {:ok, {:put, cli_session}}

    # Starts the peer's Group and cache under a process of their own, which
    # :peer.call's would not be.
    def start_web_node() do
      parent = self()

      spawn(fn ->
        {:ok, _} = Group.start_link(name: NervesHub.Group)
        :ok = Group.connect(NervesHub.Group, "web")
        {:ok, _} = NervesHub.CLISessionCache.start_link([])
        send(parent, :started)
        Process.sleep(:infinity)
      end)

      receive do
        :started -> :ok
      end
    end
  end
  """

  setup_all do
    started_distribution? = not Node.alive?()
    if started_distribution?, do: restart_group(&start_distribution/0)
    Code.compile_string(@probe)
    {:ok, peer, peer_node} = start_peer()

    on_exit(fn ->
      :peer.stop(peer)
      if started_distribution?, do: restart_group(&Node.stop/0)
    end)

    %{peer: peer, peer_node: peer_node}
  end

  setup %{peer: peer, peer_node: peer_node} do
    CLISessionCache.clear()
    :ok = :peer.call(peer, CLISessionCache, :clear, [])

    on_exit(fn -> CLISessionCache.clear() end)

    # Both nodes have to see both owners before they agree on any login's.
    both = Enum.sort([node(), peer_node])
    :ok = wait_until(fn -> owner_nodes(&CLISessionCache.owners/1) == both end)
    :ok = wait_until(fn -> owner_nodes(&:peer.call(peer, CLISessionCache, :owners, [&1])) == both end)

    :ok
  end

  defp owner_nodes(owners), do: "any token" |> owners.() |> Enum.map(&node/1) |> Enum.sort()

  test "both nodes pick the same owner for a login", %{peer: peer} do
    for _ <- 1..50 do
      token = Ecto.UUID.generate()
      here = Enum.map(CLISessionCache.owners(token), &node/1)

      assert Enum.map(:peer.call(peer, CLISessionCache, :owners, [token]), &node/1) == here
    end
  end

  test "logins are spread over both owners", %{peer_node: peer_node} do
    owners = for _ <- 1..200, do: owner_of(Ecto.UUID.generate())

    assert node() in owners
    assert peer_node in owners
  end

  test "a change to a login runs on its owner, whichever node asks", %{peer: peer, peer_node: peer_node} do
    token = token_owned_by(peer_node)

    assert CLISessionCache.get_and_update(token, {CLISessionCacheProbe, :where, []}) == peer_node
    assert :peer.call(peer, CLISessionCache, :get_and_update, [token, {CLISessionCacheProbe, :where, []}]) == peer_node
  end

  test "the owner holds a write before the caller's call returns", %{peer: peer, peer_node: peer_node} do
    token = token_owned_by(peer_node)
    cli_session = waiting_session(token)

    assert CLISessionCache.get_and_update(token, {Accounts, :store_new_cli_session, [cli_session]}) ==
             {:ok, cli_session}

    assert :peer.call(peer, CLISessionCache, :get, [token]) == {:ok, cli_session}
    # And replicates it back here, as a write always has.
    assert :ok = wait_until(fn -> CLISessionCache.get(token) == {:ok, cli_session} end)
  end

  test "a login confirmed on both nodes at once mints one API token", %{peer: peer} do
    user = Fixtures.user_fixture()
    # The peer has no database, so a confirmation it made itself would raise.
    # Every one coming back :ok means each ran here, on the owner.
    token = token_owned_by(node())
    :ok = store(token, waiting_session(token))
    :ok = wait_until(fn -> match?({:ok, _}, :peer.call(peer, CLISessionCache, :get, [token])) end)

    there =
      for _ <- 1..5,
          do: Task.async(fn -> :peer.call(peer, Accounts, :verify_cli_session_token, [user, token]) end)

    here = for _ <- 1..5, do: Task.async(fn -> Accounts.verify_cli_session_token(user, token) end)

    assert Enum.all?(Task.await_many(there ++ here), &(&1 == :ok))
    assert [_one] = Accounts.get_user_api_tokens(user)
  end

  test "a ready login's token is collected once across both nodes", %{peer: peer, peer_node: peer_node} do
    # The peer owns it, so polls here go to the peer, and this node's copy is
    # never what answers.
    token = token_owned_by(peer_node)
    :ok = store(token, %{waiting_session(token) | status: :ready, user_id: 1, user_token: "nhu_collect_me"})

    here = for _ <- 1..5, do: Task.async(fn -> Accounts.check_cli_session_ready(token) end)
    there = for _ <- 1..5, do: Task.async(fn -> :peer.call(peer, Accounts, :check_cli_session_ready, [token]) end)

    collected =
      (here ++ there)
      |> Task.await_many()
      |> Enum.map(fn {:ok, cli_session} -> {cli_session.status, cli_session.user_token} end)

    assert Enum.count(collected, &(&1 == {:ready, "nhu_collect_me"})) == 1
    assert Enum.count(collected, &(&1 == {:collected, nil})) == 9
  end

  test "an owner whose node has gone is skipped for the next" do
    {:ok, gone_peer, _gone_node} = start_peer()
    gone = :peer.call(gone_peer, Process, :whereis, [CLISessionCache])
    :ok = :peer.stop(gone_peer)

    assert CLISessionCache.call_owners(
             [gone, Process.whereis(CLISessionCache)],
             "token",
             {CLISessionCacheProbe, :where, []}
           ) ==
             node()
  end

  defp store(token, cli_session) do
    CLISessionCache.get_and_update(token, {CLISessionCacheProbe, :store, [cli_session]})
  end

  defp owner_of(token), do: token |> CLISessionCache.owners() |> hd() |> node()

  defp token_owned_by(owner) do
    token = Ecto.UUID.generate()
    if owner_of(token) == owner, do: token, else: token_owned_by(owner)
  end

  defp waiting_session(token) do
    now = DateTime.utc_now()

    %UserCLISession{
      token: token,
      status: :waiting,
      requested_at: DateTime.to_unix(now),
      expires_at: now |> DateTime.add(5, :minute) |> DateTime.to_unix(),
      confirmation_code: 12_345_678,
      note: "nh"
    }
  end

  # Group names its members' node when it starts, so one started before this
  # node had a name replicates them as `nonode@nohost`, which no peer can
  # reach. So `NervesHub.GroupSupervisor`, and this node's cache with it, is
  # stopped while `rename` names the node, and started again under the new
  # name. A running Group crashes when its own node's name changes.
  defp restart_group(rename) do
    :ok = Supervisor.terminate_child(NervesHub.Supervisor, NervesHub.GroupSupervisor)
    _ = rename.()
    {:ok, _} = Supervisor.restart_child(NervesHub.Supervisor, NervesHub.GroupSupervisor)
    :ok
  end

  defp start_distribution() do
    # Node.start/2 needs epmd and does not start it.
    {_, 0} = System.cmd("epmd", ["-daemon"], env: [])
    {:ok, _} = Node.start(:"cli_session_cache_test@127.0.0.1", :longnames)
  end

  defp start_peer() do
    code_path = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])

    {:ok, pid, name} =
      :peer.start(%{
        name: :peer.random_name(~c"cli_session_cache_peer"),
        host: ~c"127.0.0.1",
        longnames: true,
        connection: :standard_io,
        args:
          [~c"-setcookie", Atom.to_charlist(Node.get_cookie()), ~c"-kernel", ~c"connect_all", ~c"false"] ++ code_path
      })

    true = Node.connect(name)

    {:ok, _} = :peer.call(pid, :application, :ensure_all_started, [:elixir])
    # Skips the cache's warm-up and expiry timers, as in this node's tests, so
    # it owns logins as soon as it starts.
    :ok = :peer.call(pid, :application, :set_env, [:nerves_hub, :env, :test])
    _ = :peer.call(pid, Code, :compile_string, [@probe])
    :ok = :peer.call(pid, CLISessionCacheProbe, :start_web_node, [])

    {:ok, pid, name}
  end

  defp wait_until(fun, attempts \\ 250) do
    cond do
      fun.() ->
        :ok

      attempts == 0 ->
        {:error, :timeout}

      true ->
        Process.sleep(20)
        wait_until(fun, attempts - 1)
    end
  end
end
