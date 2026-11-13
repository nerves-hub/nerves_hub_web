defmodule NervesHubWeb.Integrations.Slack.SocketTest do
  # A real WebSocket server standing in for Slack's: the point of the module is
  # the connection, which a stub would skip.
  use NervesHub.DataCase, async: false

  alias NervesHub.Fixtures
  alias NervesHub.Integrations.Slack
  alias NervesHubWeb.Integrations.Slack.Socket

  defmodule FakeSlack do
    @moduledoc false
    @behaviour WebSock

    def init(%{test: test} = state) do
      send(test, {:server, self()})
      {:push, {:text, Jason.encode!(%{type: "hello", num_connections: 1})}, state}
    end

    def handle_in({text, opcode: :text}, state) do
      send(state.test, {:from_nerveshub, Jason.decode!(text)})
      {:ok, state}
    end

    def handle_in(_frame, state), do: {:ok, state}

    def handle_control({data, opcode: :pong}, state) do
      send(state.test, {:pong, data})
      {:ok, state}
    end

    def handle_control(_frame, state), do: {:ok, state}

    def handle_info({:push, message}, state), do: {:push, {:text, Jason.encode!(message)}, state}
    def handle_info({:ping, data}, state), do: {:push, {:ping, data}, state}

    def terminate(_reason, _state), do: :ok
  end

  defmodule FakeSlackPlug do
    @moduledoc false
    def init(test), do: test

    def call(conn, test) do
      conn
      |> WebSockAdapter.upgrade(FakeSlack, %{test: test}, timeout: 60_000)
      |> Plug.Conn.halt()
    end
  end

  setup context do
    test_pid = self()

    server =
      start_supervised!(
        {Bandit, plug: {FakeSlackPlug, test_pid}, ip: :loopback, port: 0, startup_log: false},
        id: :fake_slack
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    # The connection runs in its own process, which a private stub would not
    # reach.
    :ok = Req.Test.set_req_test_to_shared(context)
    on_exit(fn -> Req.Test.set_req_test_to_private() end)

    Req.Test.stub(Slack, fn conn ->
      send(test_pid, {:opened, Plug.Conn.get_req_header(conn, "authorization")})
      Req.Test.json(conn, %{"ok" => true, "url" => "ws://127.0.0.1:#{port}/link/?ticket=abc"})
    end)

    start_supervised!({Socket, app_token: "xapp-test-token", notify: test_pid})

    assert_receive {:opened, ["Bearer xapp-test-token"]}, 2000
    assert_receive {:slack_socket, :connected}, 2000
    assert_receive {:server, server_pid}, 2000

    %{server: server_pid}
  end

  defp envelope(server, id, type, payload) do
    send(
      server,
      {:push, %{envelope_id: id, type: type, accepts_response_payload: type != "events_api", payload: payload}}
    )
  end

  defp eventually(fun, tries \\ 40) do
    cond do
      fun.() -> true
      tries == 0 -> flunk("did not happen")
      true -> Process.sleep(50) && eventually(fun, tries - 1)
    end
  end

  test "answers a slash command with the acknowledgement", %{server: server} do
    envelope(server, "e1", "slash_commands", %{
      "team_id" => "T0ACME",
      "user_id" => "U0ALICE",
      "command" => "/nerveshub",
      "text" => "help",
      "trigger_id" => "1728.1.socket"
    })

    assert_receive {:from_nerveshub,
                    %{"envelope_id" => "e1", "payload" => %{"response_type" => "ephemeral", "text" => text}}},
                   2000

    assert text =~ "`/nerveshub device <identifier>`"
  end

  test "acknowledges a button click, and hands it on", %{server: server} do
    envelope(server, "e2", "interactive", %{
      "type" => "block_actions",
      "team" => %{"id" => "T0ACME"},
      "user" => %{"id" => "U0ALICE"},
      "actions" => [%{"action_id" => "device.open"}]
    })

    assert_receive {:from_nerveshub, ack}, 2000
    assert ack == %{"envelope_id" => "e2"}
  end

  test "acknowledges an event, and acts on it", %{server: server} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    _connection = Fixtures.slack_connection_fixture(org, user, %{team_id: "T0SOCKET"})

    envelope(server, "e3", "events_api", %{
      "type" => "event_callback",
      "team_id" => "T0SOCKET",
      "event" => %{"type" => "app_uninstalled"}
    })

    assert_receive {:from_nerveshub, %{"envelope_id" => "e3"}}, 2000
    eventually(fn -> Slack.list_connections(org) == [] end)
  end

  test "opens a new connection when Slack replaces this one", %{server: server} do
    send(server, {:push, %{type: "disconnect", reason: "refresh_requested"}})

    assert_receive {:opened, ["Bearer xapp-test-token"]}, 2000
    assert_receive {:slack_socket, :connected}, 2000
  end

  test "answers a ping", %{server: server} do
    send(server, {:ping, "are you there"})
    assert_receive {:pong, "are you there"}, 2000
  end
end
