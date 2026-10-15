defmodule NervesHub.Integrations.Slack.Client do
  @moduledoc """
  The Slack Web API methods NervesHub calls.

  Slack answers most failures with HTTP 200 and `"ok": false`, so every
  answer is read for `ok`, and a failure comes back as Slack's error code
  (`"invalid_code"`, `"token_revoked"`, ...) or a description of what went
  wrong on the way there. A `429` comes back as `{:rate_limited, seconds}`,
  from Slack's `Retry-After`.
  """

  alias NervesHub.Integrations.Slack

  @base_url "https://slack.com/api"

  # More channels than this many pages of them is more than a picker can
  # usefully show, and each page is a request.
  @max_channel_pages 5

  @type error() :: String.t() | {:rate_limited, pos_integer()}

  @typedoc "A channel the app can post to."
  @type channel() :: %{id: String.t(), name: String.t(), private: boolean()}

  @doc """
  Exchanges the code Slack's OAuth flow returned for the workspace's bot
  token (`oauth.v2.access`). `redirect_uri` must be the one the flow started
  with.
  """
  @spec oauth_access(String.t(), String.t()) :: {:ok, map()} | {:error, error()}
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
  @spec revoke(String.t()) :: {:ok, map()} | {:error, error()}
  def revoke(token) do
    post("auth.revoke", form: [], auth: {:bearer, token})
  end

  @doc """
  Posts a message to a channel (`chat.postMessage`). Links in it are not
  unfurled: they point at NervesHub pages that need signing in.
  """
  @spec post_message(String.t(), String.t(), %{text: String.t(), blocks: [map()]}) :: {:ok, map()} | {:error, error()}
  def post_message(token, channel_id, %{text: text, blocks: blocks}) do
    post("chat.postMessage",
      json: %{channel: channel_id, text: text, blocks: blocks, unfurl_links: false, unfurl_media: false},
      auth: {:bearer, token}
    )
  end

  @doc """
  The channels the app can post to (`conversations.list`), by name: every
  public channel, and the private channels the app has been invited to.
  Archived channels are left out.
  """
  @spec list_channels(String.t()) :: {:ok, [channel()]} | {:error, error()}
  def list_channels(token), do: list_channels(token, nil, [], 1)

  defp list_channels(token, cursor, channels, page) do
    form =
      [types: "public_channel,private_channel", exclude_archived: true, limit: 200] ++
        if(cursor, do: [cursor: cursor], else: [])

    with {:ok, %{"channels" => listed} = body} <- post("conversations.list", form: form, auth: {:bearer, token}) do
      channels =
        channels ++
          for(%{"id" => id, "name" => name} = c <- listed, do: %{id: id, name: name, private: c["is_private"] == true})

      case get_in(body, ["response_metadata", "next_cursor"]) do
        next when is_binary(next) and next != "" and page < @max_channel_pages ->
          list_channels(token, next, channels, page + 1)

        _done ->
          {:ok, Enum.sort_by(channels, & &1.name)}
      end
    end
  end

  defp post(method, opts) do
    [method: :post, base_url: @base_url, url: method, retry: false, receive_timeout: 10_000]
    |> Keyword.merge(opts)
    |> Keyword.merge(Slack.config(:req_options) || [])
    |> Req.request()
    |> case do
      {:ok, %Req.Response{status: 200, body: %{"ok" => true} = body}} -> {:ok, body}
      {:ok, %Req.Response{status: 429} = response} -> {:error, {:rate_limited, retry_after(response)}}
      {:ok, %Req.Response{body: %{"ok" => false, "error" => error}}} -> {:error, error}
      {:ok, %Req.Response{status: status}} -> {:error, "HTTP #{status}"}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end

  defp retry_after(response) do
    with [value | _] <- Req.Response.get_header(response, "retry-after"),
         {seconds, ""} when seconds > 0 <- Integer.parse(value) do
      seconds
    else
      _ -> 30
    end
  end
end
