defmodule NervesHubWeb.Integrations.Slack.OAuthControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Integrations.Slack
  alias NervesHub.Repo

  defp install_path(org), do: ~p"/org/#{org}/settings/integrations/slack/install"

  defp stub_oauth(answer) do
    Req.Test.stub(Slack, &Req.Test.json(&1, answer))
  end

  defp oauth_answer() do
    %{
      "ok" => true,
      "access_token" => "xoxb-a-bot-token",
      "token_type" => "bot",
      "scope" => "chat:write",
      "bot_user_id" => "U0KRQLJ9H",
      "app_id" => "A0KRD7HC3",
      "team" => %{"name" => "Acme Fleet", "id" => "T9TK3CUKW"},
      "is_enterprise_install" => false
    }
  end

  # Starts an install, and returns the conn carrying its session and the state
  # Slack would send back.
  defp start_install(conn, org) do
    conn = post(conn, install_path(org))
    "https://slack.com/oauth/v2/authorize?" <> query = redirected_to(conn, 302)

    {recycle(conn), URI.decode_query(query)}
  end

  test "install sends an admin to Slack, with a state for the callback", %{conn: conn, org: org} do
    {_conn, query} = start_install(conn, org)

    assert %{"client_id" => "test-client-id", "state" => state, "redirect_uri" => redirect_uri} = query
    assert byte_size(state) >= 40
    assert redirect_uri == url(~p"/integrations/slack/oauth/callback")
  end

  test "install is for admins only", %{conn: conn, org: org} do
    Repo.update_all(OrgUser, set: [role: :manage])

    assert_error_sent(401, fn -> post(conn, install_path(org)) end)
  end

  test "the callback connects the workspace and returns to the Integrations page", %{conn: conn, org: org} do
    {conn, %{"state" => state}} = start_install(conn, org)
    stub_oauth(oauth_answer())

    conn = get(conn, ~p"/integrations/slack/oauth/callback?#{[code: "a-code", state: state]}")

    assert redirected_to(conn) == ~p"/org/#{org}/settings/integrations"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Connected the Acme Fleet Slack workspace."
    assert [%{workspace: %{team_id: "T9TK3CUKW"}}] = Slack.list_connections(org)
  end

  test "the callback refuses a state it did not give out", %{conn: conn, org: org} do
    {conn, _query} = start_install(conn, org)
    stub_oauth(oauth_answer())

    conn = get(conn, ~p"/integrations/slack/oauth/callback?#{[code: "a-code", state: "forged"]}")

    assert redirected_to(conn) == ~p"/orgs"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "did not start here"
    assert Slack.list_connections(org) == []
  end

  test "the callback only works once", %{conn: conn, org: org} do
    {conn, %{"state" => state}} = start_install(conn, org)
    stub_oauth(oauth_answer())

    conn = get(conn, ~p"/integrations/slack/oauth/callback?#{[code: "a-code", state: state]}")
    conn = conn |> recycle() |> get(~p"/integrations/slack/oauth/callback?#{[code: "a-code", state: state]}")

    assert redirected_to(conn) == ~p"/orgs"
  end

  test "the callback checks the role again", %{conn: conn, org: org} do
    {conn, %{"state" => state}} = start_install(conn, org)
    Repo.update_all(OrgUser, set: [role: :manage])

    assert_error_sent(401, fn -> get(conn, ~p"/integrations/slack/oauth/callback?#{[code: "a-code", state: state]}") end)

    assert Slack.list_connections(org) == []
  end

  test "the callback says so when the person cancelled at Slack", %{conn: conn, org: org} do
    {conn, %{"state" => state}} = start_install(conn, org)

    conn = get(conn, ~p"/integrations/slack/oauth/callback?#{[error: "access_denied", state: state]}")

    assert redirected_to(conn) == ~p"/org/#{org}/settings/integrations"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Slack was not connected."
  end

  test "the callback passes on Slack's refusal", %{conn: conn, org: org} do
    {conn, %{"state" => state}} = start_install(conn, org)
    stub_oauth(%{"ok" => false, "error" => "invalid_code"})

    conn = get(conn, ~p"/integrations/slack/oauth/callback?#{[code: "a-code", state: state]}")

    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Slack could not be connected: invalid_code"
  end

  test "install is not found when the instance has no Slack app", %{conn: conn, org: org} do
    config = Application.get_env(:nerves_hub, Slack)
    on_exit(fn -> Application.put_env(:nerves_hub, Slack, config) end)
    Application.put_env(:nerves_hub, Slack, Keyword.put(config, :client_id, nil))

    assert_error_sent(404, fn -> post(conn, install_path(org)) end)
  end
end
