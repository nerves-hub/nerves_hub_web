defmodule NervesHubWeb.Integrations.Slack.VerifyRequest do
  @moduledoc """
  Refuses a request that Slack did not sign (`NervesHub.Integrations.Slack.Signature`).

  The signature covers the raw request body, which `Plug.Parsers` would
  otherwise have consumed by now; `NervesHubWeb.Plugs.CacheRawBody` keeps a
  copy of it for paths under `/integrations/`.

  Answers 404 when the instance has no Slack app, or one that only takes
  Slack's requests over Socket Mode (no signing secret), as if the routes did
  not exist.
  """
  @behaviour Plug

  import Plug.Conn

  alias NervesHub.Integrations.Slack
  alias NervesHub.Integrations.Slack.Signature

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with true <- Slack.request_urls?() || :not_configured,
         [timestamp] <- get_req_header(conn, "x-slack-request-timestamp"),
         [signature] <- get_req_header(conn, "x-slack-signature"),
         body when is_binary(body) <- conn.assigns[:raw_body],
         :ok <- Signature.verify(Slack.config(:signing_secret), timestamp, body, signature) do
      conn
    else
      :not_configured -> conn |> send_resp(404, "") |> halt()
      _unsigned -> conn |> send_resp(401, "") |> halt()
    end
  end
end
