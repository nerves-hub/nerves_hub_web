defmodule NervesHubWeb.Integrations.Slack.CommandsControllerTest do
  use NervesHubWeb.ConnCase, async: false

  alias NervesHub.Integrations.Slack.Signature

  defp send_command(conn, form, opts \\ []) do
    body = URI.encode_query(form)
    timestamp = Integer.to_string(System.os_time(:second))
    signature = Keyword.get(opts, :signature, Signature.sign("test-signing-secret", timestamp, body))

    conn
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("x-slack-request-timestamp", timestamp)
    |> put_req_header("x-slack-signature", signature)
    |> post(~p"/integrations/slack/commands", body)
  end

  test "answers a signed command", %{conn: conn} do
    form = %{"team_id" => "T0ACME", "user_id" => "U0ALICE", "command" => "/nerveshub", "text" => "help"}

    assert %{"response_type" => "ephemeral", "text" => text} = conn |> send_command(form) |> json_response(200)
    assert text =~ "/nerveshub device"
  end

  test "refuses a command Slack did not sign", %{conn: conn} do
    form = %{"team_id" => "T0ACME", "user_id" => "U0ALICE", "text" => "help"}

    assert conn |> send_command(form, signature: "v0=forged") |> response(401)
  end
end
