defmodule NervesHub.CLISessionCacheTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Accounts
  alias NervesHub.Accounts.UserCLISession
  alias NervesHub.CLISessionCache
  alias NervesHub.Fixtures

  setup do
    CLISessionCache.clear()

    on_exit(fn ->
      CLISessionCache.clear()
    end)
  end

  test "applying a :put broadcast from another node does not re-broadcast (no cluster storm)" do
    # Simulate a broadcast arriving from a peer node by joining the group as if
    # we were a remote CLISessionCache and sending the GenServer the same message
    # Group.dispatch would deliver.
    :ok = Group.join(NervesHub.Group, "cli_session_cache", %{}, cluster: "web")

    token = Ecto.UUID.generate()

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(5, :minute)
      |> DateTime.to_unix()

    session = %UserCLISession{token: token, status: :waiting, expires_at: expires_at}

    send(CLISessionCache, {:put, :peer@example, token, session})

    # The value must be applied locally...
    assert eventually(fn -> CLISessionCache.get(token) == {:ok, session} end)

    # ...but applying it must NOT emit another broadcast, otherwise every node
    # re-emits every message it receives and they ping-pong forever.
    refute_receive {:put, _origin, ^token, _}, 200
  end

  test "warm-up excludes the local node and no-ops when it is the only cache member" do
    # The running cache has joined the "web" group, so it is the only member in
    # this single-node test cluster. Warm-up must exclude self (never RPC itself)
    # and simply no-op instead of looping or crashing.
    send(CLISessionCache, {:warm_up_from_cluster, 1})

    # Process stayed alive (mailbox drained) and nothing was warmed in.
    assert is_map(:sys.get_state(CLISessionCache))
    assert CLISessionCache.count() == 0
  end

  test "concurrent verify_cli_session_token only mints a single API token" do
    user = Fixtures.user_fixture()
    {:ok, %{token: token}} = Accounts.generate_cli_session_token("test-token")

    # Two nodes (or a double-clicked confirm / retried request) verifying the
    # same waiting session at once. The read-modify-write is not atomic, so
    # every caller can read :waiting and mint its own token.
    results =
      1..10
      |> Enum.map(fn _ ->
        Task.async(fn -> Accounts.verify_cli_session_token(user, token) end)
      end)
      |> Task.await_many(5000)

    assert Enum.all?(results, &(&1 == :ok))

    tokens = Accounts.get_user_api_tokens(user)

    assert length(tokens) == 1,
           "expected exactly one API token to be minted, got #{length(tokens)}"
  end

  defp eventually(fun, attempts \\ 50) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(5) && eventually(fun, attempts - 1)
    end
  end

  test "are cleaned up after they expire (5 mins ttl)" do
    create_cli_session(5)

    assert CLISessionCache.count() == 1

    :ok = CLISessionCache.delete_expired_sessions()

    assert CLISessionCache.count() == 1

    create_cli_session(-7)

    assert CLISessionCache.count() == 2

    :ok = CLISessionCache.delete_expired_sessions()

    assert CLISessionCache.count() == 1
  end

  test "are cleaned up after they expire" do
    create_cli_session(5)
    create_cli_session(-6)

    assert CLISessionCache.count() == 2

    :ok = CLISessionCache.delete_expired_sessions()

    assert CLISessionCache.count() == 1
  end

  test "get/1 returns :error when key does not exist" do
    assert CLISessionCache.get("nonexistent-token") == :error
  end

  test "get/1 returns {:ok, session} after put/2" do
    token = Ecto.UUID.generate()

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(5, :minute)
      |> DateTime.to_unix()

    session = %UserCLISession{token: token, status: :waiting, expires_at: expires_at}

    :ok = CLISessionCache.put(token, session)

    assert CLISessionCache.get(token) == {:ok, session}
  end

  test "get_and_update/2 with :noop action returns value without writing" do
    token = Ecto.UUID.generate()

    result = CLISessionCache.get_and_update(token, fn current -> {current, :noop} end)

    assert result == :error
    assert CLISessionCache.get(token) == :error
  end

  test "get_and_update/2 with {:put, new_session} action updates and returns value" do
    token = Ecto.UUID.generate()

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(5, :minute)
      |> DateTime.to_unix()

    session = %UserCLISession{token: token, status: :waiting, expires_at: expires_at}
    updated = %UserCLISession{token: token, status: :complete, expires_at: expires_at}

    :ok = CLISessionCache.put(token, session)

    result =
      CLISessionCache.get_and_update(token, fn {:ok, _} -> {:updated, {:put, updated}} end)

    assert result == :updated
    assert CLISessionCache.get(token) == {:ok, updated}
  end

  test "get_and_update/2 when callback raises — GenServer survives" do
    token = Ecto.UUID.generate()

    assert_raise RuntimeError, "boom", fn ->
      CLISessionCache.get_and_update(token, fn _ -> raise "boom" end)
    end

    assert is_map(:sys.get_state(CLISessionCache))
  end

  defp create_cli_session(mins_ago) do
    token = Ecto.UUID.generate()

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(mins_ago, :minute)
      |> DateTime.to_unix()

    cli_session = %UserCLISession{token: token, status: :waiting, expires_at: expires_at}

    :ok = NervesHub.CLISessionCache.put(token, cli_session)
  end
end
