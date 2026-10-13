defmodule NervesHub.Integrations.SlackTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.Scope
  alias NervesHub.AuditLogs
  alias NervesHub.Fixtures
  alias NervesHub.Integrations.Slack
  alias NervesHub.Integrations.Slack.Connection
  alias NervesHub.Integrations.Slack.Workspace

  @redirect_uri "https://nerves-hub.example.com/integrations/slack/oauth/callback"

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)

    %{org: org, scope: %Scope{org: org, user: user, role: :admin}, user: user}
  end

  # What `oauth.v2.access` answers for a bot install.
  defp access(overrides \\ %{}) do
    Map.merge(
      %{
        "ok" => true,
        "access_token" => "xoxb-test-bot-token",
        "token_type" => "bot",
        "scope" => "chat:write,chat:write.public,channels:read,groups:read,commands",
        "bot_user_id" => "U0KRQLJ9H",
        "app_id" => "A0KRD7HC3",
        "team" => %{"name" => "Acme Fleet", "id" => "T9TK3CUKW"},
        "enterprise" => nil,
        "authed_user" => %{"id" => "U1234"},
        "is_enterprise_install" => false
      },
      overrides
    )
  end

  defp stub_slack(answers) do
    test_pid = self()

    Req.Test.stub(Slack, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      method = conn.path_info |> List.last()
      send(test_pid, {:slack, method, Plug.Conn.get_req_header(conn, "authorization"), URI.decode_query(body)})
      Req.Test.json(conn, Map.fetch!(answers, method))
    end)
  end

  defp connect!(scope, access \\ access()) do
    stub_slack(%{"oauth.v2.access" => access, "auth.revoke" => %{"ok" => true, "revoked" => true}})
    {:ok, connection} = Slack.connect(scope, "a-code", @redirect_uri)
    connection
  end

  describe "connect/3" do
    test "exchanges the code, and connects the workspace to the organization", %{org: org, scope: scope, user: user} do
      stub_slack(%{"oauth.v2.access" => access()})

      assert {:ok, %Connection{} = connection} = Slack.connect(scope, "a-code", @redirect_uri)

      assert_received {:slack, "oauth.v2.access", ["Basic " <> credentials], params}
      assert Base.decode64!(credentials) == "test-client-id:test-client-secret"
      assert params == %{"code" => "a-code", "redirect_uri" => @redirect_uri}

      assert %Workspace{
               team_id: "T9TK3CUKW",
               team_name: "Acme Fleet",
               bot_user_id: "U0KRQLJ9H",
               bot_token: "xoxb-test-bot-token",
               scopes: ["chat:write", "chat:write.public", "channels:read", "groups:read", "commands"]
             } = connection.workspace

      assert connection.org_id == org.id
      assert connection.connected_by_id == user.id

      assert [log] = AuditLogs.logs_for(org)
      assert log.description =~ "connected Slack workspace Acme Fleet (T9TK3CUKW)"
    end

    test "keeps the bot token encrypted in the database", %{scope: scope} do
      connect!(scope)

      %Postgrex.Result{rows: [[stored]]} = Repo.query!("SELECT bot_token FROM slack_workspaces")

      refute stored =~ "xoxb"
    end

    test "installing again refreshes the token, without connecting twice", %{org: org, scope: scope} do
      connect!(scope)
      connect!(scope, access(%{"access_token" => "xoxb-new-token", "scope" => "chat:write"}))

      assert [%Connection{workspace: %Workspace{bot_token: "xoxb-new-token", scopes: ["chat:write"]}}] =
               Slack.list_connections(org)

      assert Repo.aggregate(Workspace, :count) == 1
    end

    test "two organizations can connect the same workspace", %{scope: scope, user: user} do
      other_org = Fixtures.org_fixture(user, %{name: "elsewhere"})

      first = connect!(scope)
      second = connect!(%{scope | org: other_org})

      assert first.workspace_id == second.workspace_id
      assert Repo.aggregate(Workspace, :count) == 1
    end

    test "refuses an organization-wide Enterprise Grid install", %{org: org, scope: scope} do
      stub_slack(%{"oauth.v2.access" => access(%{"is_enterprise_install" => true, "team" => nil})})

      assert {:error, :enterprise_install} = Slack.connect(scope, "a-code", @redirect_uri)
      assert Slack.list_connections(org) == []
    end

    test "passes on Slack's error", %{org: org, scope: scope} do
      stub_slack(%{"oauth.v2.access" => %{"ok" => false, "error" => "invalid_code"}})

      assert {:error, "invalid_code"} = Slack.connect(scope, "a-code", @redirect_uri)
      assert Slack.list_connections(org) == []
    end
  end

  describe "disconnect/2" do
    test "revokes the token and forgets the workspace when no organization is left", %{org: org, scope: scope} do
      connection = connect!(scope)

      assert :ok = Slack.disconnect(scope, connection)

      assert_received {:slack, "auth.revoke", ["Bearer xoxb-test-bot-token"], _}
      assert Slack.list_connections(org) == []
      assert Repo.aggregate(Workspace, :count) == 0

      assert [disconnected, _connected] = AuditLogs.logs_for(org)
      assert disconnected.description =~ "disconnected Slack workspace Acme Fleet"
    end

    test "keeps the token while another organization still uses it", %{scope: scope, user: user} do
      other_org = Fixtures.org_fixture(user, %{name: "elsewhere"})
      connection = connect!(scope)
      connect!(%{scope | org: other_org})

      assert :ok = Slack.disconnect(scope, connection)

      refute_received {:slack, "auth.revoke", _, _}
      assert [%Connection{}] = Slack.list_connections(other_org)
    end

    test "still disconnects when Slack cannot revoke the token", %{org: org, scope: scope} do
      connection = connect!(scope)
      stub_slack(%{"auth.revoke" => %{"ok" => false, "error" => "invalid_auth"}})

      assert :ok = Slack.disconnect(scope, connection)
      assert Slack.list_connections(org) == []
    end
  end

  describe "handle_event/2" do
    setup %{scope: scope, user: user} do
      other_org = Fixtures.org_fixture(user, %{name: "elsewhere"})
      connect!(scope)
      connect!(%{scope | org: other_org})

      %{other_org: other_org}
    end

    test "the app being removed disconnects every organization", %{org: org, other_org: other_org} do
      assert :ok = Slack.handle_event("T9TK3CUKW", %{"type" => "app_uninstalled"})

      assert Slack.list_connections(org) == []
      assert Slack.list_connections(other_org) == []
      assert Repo.aggregate(Workspace, :count) == 0

      assert [removed, _connected] = AuditLogs.logs_for(org)
      assert removed.description =~ "was disconnected because the app was removed from it"
      assert removed.actor_type == Org

      # Slack retries events it thinks were missed.
      assert :ok = Slack.handle_event("T9TK3CUKW", %{"type" => "app_uninstalled"})
    end

    test "only the bot token being revoked disconnects", %{org: org} do
      assert :ok =
               Slack.handle_event("T9TK3CUKW", %{
                 "type" => "tokens_revoked",
                 "tokens" => %{"oauth" => ["U1234"], "bot" => []}
               })

      assert [_] = Slack.list_connections(org)

      assert :ok =
               Slack.handle_event("T9TK3CUKW", %{
                 "type" => "tokens_revoked",
                 "tokens" => %{"bot" => ["U0KRQLJ9H"]}
               })

      assert Slack.list_connections(org) == []
    end

    test "ignores other workspaces and other events", %{org: org} do
      assert :ok = Slack.handle_event("T000000", %{"type" => "app_uninstalled"})
      assert :ok = Slack.handle_event("T9TK3CUKW", %{"type" => "app_mention"})

      assert [_] = Slack.list_connections(org)
    end
  end

  test "authorize_url/2 asks for the app's scopes and carries the state" do
    url = URI.parse(Slack.authorize_url("a-state", @redirect_uri))

    assert url.host == "slack.com"
    assert url.path == "/oauth/v2/authorize"

    assert %{
             "client_id" => "test-client-id",
             "scope" => "chat:write,chat:write.public,channels:read,groups:read,commands",
             "redirect_uri" => @redirect_uri,
             "state" => "a-state"
           } = URI.decode_query(url.query)
  end

  test "configured?/0 needs the client id, client secret and signing secret" do
    assert Slack.configured?()

    config = Application.get_env(:nerves_hub, Slack)
    on_exit(fn -> Application.put_env(:nerves_hub, Slack, config) end)

    Application.put_env(:nerves_hub, Slack, Keyword.put(config, :signing_secret, nil))
    refute Slack.configured?()
  end
end
