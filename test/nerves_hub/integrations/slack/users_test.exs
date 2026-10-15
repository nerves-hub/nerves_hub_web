defmodule NervesHub.Integrations.Slack.UsersTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Fixtures
  alias NervesHub.Integrations.Slack
  alias NervesHub.Integrations.Slack.UserLink
  alias NervesHub.Integrations.Slack.Users

  @redirect_uri "https://nerves-hub.example.com/integrations/slack/link/callback"

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    Fixtures.slack_connection_fixture(org, user, %{team_id: "T0ACME", team_name: "Acme Fleet"})

    %{user: user}
  end

  # Slack's answers for a sign-in by `slack_user_id` in `team_id`.
  defp stub_sign_in(slack_user_id, team_id \\ "T0ACME") do
    test_pid = self()

    Req.Test.stub(Slack, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:slack, List.last(conn.path_info), Plug.Conn.get_req_header(conn, "authorization"), body})

      case List.last(conn.path_info) do
        "openid.connect.token" ->
          Req.Test.json(conn, %{"ok" => true, "access_token" => "xoxp-test-user-token", "id_token" => "x"})

        "openid.connect.userInfo" ->
          Req.Test.json(conn, %{
            "ok" => true,
            "sub" => slack_user_id,
            "https://slack.com/user_id" => slack_user_id,
            "https://slack.com/team_id" => team_id,
            "https://slack.com/team_name" => "Acme Fleet",
            "name" => "Alice Smith"
          })
      end
    end)
  end

  test "authorize_url/3 asks Slack for an OpenID sign-in, suggesting the workspace" do
    url = URI.parse(Users.authorize_url("a-state", @redirect_uri, "T0ACME"))

    assert url.host == "slack.com"
    assert url.path == "/openid/connect/authorize"

    assert %{
             "response_type" => "code",
             "scope" => "openid profile",
             "client_id" => "test-client-id",
             "state" => "a-state",
             "redirect_uri" => @redirect_uri,
             "team" => "T0ACME"
           } = URI.decode_query(url.query)
  end

  test "links the Slack user Slack says signed in", %{user: user} do
    stub_sign_in("U0ALICE")

    assert {:ok, %UserLink{slack_user_id: "U0ALICE", team_id: "T0ACME", slack_name: "Alice Smith"}} =
             Users.link(user, "a-code", @redirect_uri)

    assert_received {:slack, "openid.connect.token", [], token_body}

    assert %{"code" => "a-code", "redirect_uri" => @redirect_uri, "client_secret" => "test-client-secret"} =
             URI.decode_query(token_body)

    assert_received {:slack, "openid.connect.userInfo", ["Bearer xoxp-test-user-token"], _}

    assert Users.linked_user("T0ACME", "U0ALICE").id == user.id
    assert is_nil(Users.linked_user("T0ACME", "U0BOB"))
    assert is_nil(Users.linked_user("T0OTHER", "U0ALICE"))
  end

  test "using a link records when, and looking it up does not", %{user: user} do
    stub_sign_in("U0ALICE")
    {:ok, %UserLink{last_used_at: nil}} = Users.link(user, "a-code", @redirect_uri)

    assert Users.linked_user("T0ACME", "U0ALICE").id == user.id
    assert [%{link: %UserLink{last_used_at: nil}}] = Users.list_links(user)

    assert Users.use_link("T0ACME", "U0ALICE").id == user.id
    assert [%{link: %UserLink{last_used_at: %DateTime{}}}] = Users.list_links(user)

    assert is_nil(Users.use_link("T0ACME", "U0BOB"))
  end

  test "signing in again moves the Slack user to whoever signed in", %{user: user} do
    stub_sign_in("U0ALICE")
    {:ok, _} = Users.link(user, "a-code", @redirect_uri)

    other = Fixtures.user_fixture()
    {:ok, _} = Users.link(other, "another-code", @redirect_uri)

    assert Users.linked_user("T0ACME", "U0ALICE").id == other.id
    assert Users.list_links(user) == []
  end

  test "passes on Slack refusing the code", %{user: user} do
    Req.Test.stub(Slack, &Req.Test.json(&1, %{"ok" => false, "error" => "invalid_code"}))

    assert {:error, "invalid_code"} = Users.link(user, "a-code", @redirect_uri)
    assert Users.list_links(user) == []
  end

  test "lists and removes a user's links", %{user: user} do
    stub_sign_in("U0ALICE")
    {:ok, link} = Users.link(user, "a-code", @redirect_uri)

    assert [%{link: %UserLink{id: id}, team_name: "Acme Fleet"}] = Users.list_links(user)
    assert id == link.id

    :ok = Users.unlink(Fixtures.user_fixture(), link.id)
    assert [_still_there] = Users.list_links(user)

    :ok = Users.unlink(user, link.id)
    assert Users.list_links(user) == []
  end
end
