defmodule NervesHubWeb.Live.Account.SlackLinkTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Fixtures
  alias NervesHub.Integrations.Slack
  alias NervesHub.Integrations.Slack.Users

  setup %{org: org, user: user} do
    Fixtures.slack_connection_fixture(org, user, %{team_id: "T0ACME", team_name: "Acme Fleet"})

    Req.Test.stub(Slack, fn conn ->
      case List.last(conn.path_info) do
        "openid.connect.token" ->
          Req.Test.json(conn, %{"ok" => true, "access_token" => "xoxp-test-user-token"})

        "openid.connect.userInfo" ->
          Req.Test.json(conn, %{
            "ok" => true,
            "https://slack.com/user_id" => "U0ALICE",
            "https://slack.com/team_id" => "T0ACME",
            "https://slack.com/team_name" => "Acme Fleet",
            "name" => "Alice Smith"
          })
      end
    end)

    :ok
  end

  # Starts a sign-in, as the page's button does, and returns the conn
  # carrying its session and the state Slack would send back.
  defp start_sign_in(conn) do
    conn = post(conn, "/integrations/slack/link/start", %{"team" => "T0ACME"})
    "https://slack.com/openid/connect/authorize?" <> query = redirected_to(conn, 302)

    {recycle(conn), URI.decode_query(query)}
  end

  test "explains what linking does, and starts a sign-in with Slack", %{conn: conn, user: user} do
    conn
    |> visit("/integrations/slack/link?team=T0ACME")
    |> assert_has("#slack-link", text: user.email)
    |> assert_has("#slack-link button", text: "Sign in with Slack")

    {_conn, query} = start_sign_in(conn)

    assert %{"team" => "T0ACME", "scope" => "openid profile", "state" => state, "redirect_uri" => redirect_uri} = query
    assert byte_size(state) >= 40
    assert redirect_uri == url(~p"/integrations/slack/link/callback")
  end

  test "links the Slack account the person signed in as", %{conn: conn, user: user} do
    {conn, %{"state" => state}} = start_sign_in(conn)

    conn = get(conn, "/integrations/slack/link/callback?" <> URI.encode_query(%{code: "a-code", state: state}))

    assert redirected_to(conn) == "/account"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Linked Alice Smith in Acme Fleet."
    assert Users.linked_user("T0ACME", "U0ALICE").id == user.id
  end

  test "refuses a sign-in that did not start in this session", %{conn: conn, user: user} do
    {conn, _query} = start_sign_in(conn)

    conn =
      get(conn, "/integrations/slack/link/callback?" <> URI.encode_query(%{code: "a-code", state: "someone-elses"}))

    assert redirected_to(conn) == "/integrations/slack/link"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "did not start here"
    assert Users.list_links(user) == []

    fresh = get(build_conn(), "/integrations/slack/link/callback?" <> URI.encode_query(%{code: "a-code", state: "x"}))
    assert redirected_to(fresh) =~ "/login"
  end

  test "drops a workspace suggestion that is not a workspace id", %{conn: conn} do
    conn = post(conn, "/integrations/slack/link/start", %{"team" => "T0ACME&scope=admin"})
    "https://slack.com/openid/connect/authorize?" <> query = redirected_to(conn, 302)

    refute Map.has_key?(URI.decode_query(query), "team")
  end

  test "the account page lists the links and can remove them", %{conn: conn, user: user} do
    {conn, %{"state" => state}} = start_sign_in(conn)
    _ = get(conn, "/integrations/slack/link/callback?" <> URI.encode_query(%{code: "a-code", state: state}))

    [%{link: link}] = Users.list_links(user)

    build_conn()
    |> Plug.Test.init_test_session(%{"user_token" => NervesHub.Accounts.create_user_session_token(user)})
    |> visit("/account")
    |> assert_has("#slack-link-#{link.id}", text: "Alice Smith")
    |> assert_has("#slack-link-#{link.id}", text: "Acme Fleet")
    |> within("#slack-link-#{link.id}", &click_button(&1, "Unlink"))
    |> assert_has("[role='alert']", text: "The Slack account was unlinked.")
    |> refute_has("#slack-links")

    assert Users.list_links(user) == []
  end
end
