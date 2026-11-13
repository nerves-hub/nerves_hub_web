defmodule NervesHubWeb.Integrations.Slack.InteractionsControllerTest do
  use NervesHubWeb.ConnCase, async: false

  alias NervesHub.Integrations.Slack.Signature

  defp send_interaction(conn, form, opts \\ []) do
    body = URI.encode_query(form)
    timestamp = Integer.to_string(System.os_time(:second))
    signature = Keyword.get(opts, :signature, Signature.sign("test-signing-secret", timestamp, body))

    conn
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("x-slack-request-timestamp", timestamp)
    |> put_req_header("x-slack-signature", signature)
    |> post(~p"/integrations/slack/interactivity", body)
  end

  test "answers a signed click straight away", %{conn: conn} do
    payload = Jason.encode!(%{"type" => "block_actions", "actions" => [%{"action_id" => "device.open"}]})

    assert conn |> send_interaction(%{"payload" => payload}) |> response(200) == ""
  end

  test "refuses a click Slack did not sign", %{conn: conn} do
    payload = Jason.encode!(%{"type" => "block_actions", "actions" => []})

    assert conn |> send_interaction(%{"payload" => payload}, signature: "v0=forged") |> response(401)
  end

  test "only reads the signed body, not the query string", %{conn: conn} do
    body = URI.encode_query(%{"other" => "x"})
    timestamp = Integer.to_string(System.os_time(:second))

    payload = Jason.encode!(%{"type" => "block_actions", "actions" => []})

    conn =
      conn
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("x-slack-request-timestamp", timestamp)
      |> put_req_header("x-slack-signature", Signature.sign("test-signing-secret", timestamp, body))
      |> post("/integrations/slack/interactivity?" <> URI.encode_query(%{"payload" => payload}), body)

    assert response(conn, 400)
  end

  test "refuses a request that is not an interaction", %{conn: conn} do
    assert conn |> send_interaction(%{"payload" => "not json"}) |> response(400)
    assert build_conn() |> send_interaction(%{"something" => "else"}) |> response(400)
  end
end
