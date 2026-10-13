defmodule NervesHub.Integrations.Slack.Client do
  @moduledoc """
  The Slack Web API methods NervesHub calls.

  Slack answers most failures with HTTP 200 and `"ok": false`, so every
  answer is read for `ok`, and a failure comes back as Slack's error code
  (`"invalid_code"`, `"token_revoked"`, ...) or a description of what went
  wrong on the way there.
  """

  alias NervesHub.Integrations.Slack

  @base_url "https://slack.com/api"

  @doc """
  Exchanges the code Slack's OAuth flow returned for the workspace's bot
  token (`oauth.v2.access`). `redirect_uri` must be the one the flow started
  with.
  """
  @spec oauth_access(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def oauth_access(code, redirect_uri) do
    post("oauth.v2.access",
      form: [code: code, redirect_uri: redirect_uri],
      auth: {:basic, "#{Slack.config(:client_id)}:#{Slack.config(:client_secret)}"}
    )
  end

  @doc """
  Revokes a bot token (`auth.revoke`), which removes NervesHub's app from
  the workspace.
  """
  @spec revoke(String.t()) :: {:ok, map()} | {:error, String.t()}
  def revoke(token) do
    post("auth.revoke", form: [], auth: {:bearer, token})
  end

  defp post(method, opts) do
    [method: :post, base_url: @base_url, url: method, retry: false, receive_timeout: 10_000]
    |> Keyword.merge(opts)
    |> Keyword.merge(Slack.config(:req_options) || [])
    |> Req.request()
    |> case do
      {:ok, %Req.Response{status: 200, body: %{"ok" => true} = body}} -> {:ok, body}
      {:ok, %Req.Response{body: %{"ok" => false, "error" => error}}} -> {:error, error}
      {:ok, %Req.Response{status: status}} -> {:error, "HTTP #{status}"}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end
end
