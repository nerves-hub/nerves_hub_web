defmodule NervesHubWeb.Integrations.Slack.EventsControllerTest do
  use NervesHubWeb.ConnCase, async: false

  alias NervesHub.Accounts.Scope
  alias NervesHub.Fixtures
  alias NervesHub.Integrations.Slack
  alias NervesHub.Integrations.Slack.Signature

  defp send_event(conn, payload, opts \\ []) do
    body = Jason.encode!(payload)
    timestamp = Integer.to_string(Keyword.get(opts, :timestamp, System.os_time(:second)))
    signature = Keyword.get(opts, :signature, Signature.sign("test-signing-secret", timestamp, body))

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-slack-request-timestamp", timestamp)
    |> put_req_header("x-slack-signature", signature)
    |> post(~p"/integrations/slack/events", body)
  end

  test "answers Slack's URL verification", %{conn: conn} do
    conn =
      send_event(conn, %{
        "type" => "url_verification",
        "challenge" => "3eZbrw1aBm2rZgRNFdxV2595E9CY3gmdALWMmHkvFXO7tYXAYM8P",
        "token" => "x"
      })

    assert json_response(conn, 200) == %{"challenge" => "3eZbrw1aBm2rZgRNFdxV2595E9CY3gmdALWMmHkvFXO7tYXAYM8P"}
  end

  test "refuses a request Slack did not sign", %{conn: conn} do
    payload = %{"type" => "url_verification", "challenge" => "x"}

    assert conn |> send_event(payload, signature: "v0=forged") |> response(401)
    assert build_conn() |> send_event(payload, timestamp: System.os_time(:second) - 600) |> response(401)

    assert build_conn()
           |> put_req_header("content-type", "application/json")
           |> post(~p"/integrations/slack/events", Jason.encode!(payload))
           |> response(401)
  end

  test "disconnects a workspace the app was removed from", %{conn: conn} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)

    Req.Test.stub(Slack, fn conn ->
      Req.Test.json(conn, %{
        "ok" => true,
        "access_token" => "xoxb-a-bot-token",
        "token_type" => "bot",
        "bot_user_id" => "U0KRQLJ9H",
        "app_id" => "A0KRD7HC3",
        "team" => %{"name" => "Acme Fleet", "id" => "T9TK3CUKW"}
      })
    end)

    {:ok, _} = Slack.connect(%Scope{org: org, user: user, role: :admin}, "a-code", "https://example.com/callback")

    payload = %{
      "type" => "event_callback",
      "team_id" => "T9TK3CUKW",
      "event" => %{"type" => "app_uninstalled"},
      "event_id" => "Ev0PV52K21"
    }

    assert conn |> send_event(payload) |> response(200)
    assert Slack.list_connections(org) == []
  end

  test "previews a NervesHub link in the background", %{conn: conn} do
    user = Fixtures.user_fixture()
    _slack = Fixtures.slack_connection_fixture(Fixtures.org_fixture(user), user, %{team_id: "T0ACME"})
    test_pid = self()

    Req.Test.stub(Slack, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:slack, conn.request_path, Jason.decode!(body)})
      Req.Test.json(conn, %{"ok" => true})
    end)

    payload = %{
      "type" => "event_callback",
      "team_id" => "T0ACME",
      "event" => %{
        "type" => "link_shared",
        "channel" => "C0FLEET",
        "message_ts" => "1728900000.000100",
        "user" => "U0NOTLINKED",
        "links" => [%{"url" => NervesHubWeb.Endpoint.url() <> "/org/acme/thermostat/devices/nh-1"}]
      }
    }

    assert conn |> send_event(payload) |> response(200)

    # The poster has not linked their account, so they are asked to.
    assert_receive {:slack, "/api/chat.unfurl", %{"user_auth_required" => true}}, 2000
  end

  test "answers events it does not handle", %{conn: conn} do
    payload = %{"type" => "event_callback", "team_id" => "T0", "event" => %{"type" => "app_mention"}}

    assert conn |> send_event(payload) |> response(200)
  end

  test "is not found when the instance has no Slack app", %{conn: conn} do
    config = Application.get_env(:nerves_hub, Slack)
    on_exit(fn -> Application.put_env(:nerves_hub, Slack, config) end)
    Application.put_env(:nerves_hub, Slack, Keyword.put(config, :signing_secret, nil))

    assert conn |> send_event(%{"type" => "url_verification", "challenge" => "x"}) |> response(404)
  end

  test "is not found when the instance hears from Slack over Socket Mode alone", %{conn: conn} do
    config = Application.get_env(:nerves_hub, Slack)
    on_exit(fn -> Application.put_env(:nerves_hub, Slack, config) end)
    Application.put_env(:nerves_hub, Slack, Keyword.merge(config, signing_secret: nil, app_token: "xapp-1"))

    assert conn |> send_event(%{"type" => "url_verification", "challenge" => "x"}) |> response(404)
  end
end
