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
  Exchanges the code from a sign-in with Slack for the user's token
  (`openid.connect.token`).
  """
  @spec openid_token(String.t(), String.t()) :: {:ok, map()} | {:error, error()}
  def openid_token(code, redirect_uri) do
    post("openid.connect.token",
      form: [
        code: code,
        redirect_uri: redirect_uri,
        client_id: Slack.config(:client_id),
        client_secret: Slack.config(:client_secret)
      ]
    )
  end

  @doc """
  Who signed in with Slack (`openid.connect.userInfo`): their Slack user id
  and workspace, under `https://slack.com/user_id` and
  `https://slack.com/team_id`, and their name.
  """
  @spec openid_user_info(String.t()) :: {:ok, map()} | {:error, error()}
  def openid_user_info(token) do
    post("openid.connect.userInfo", form: [], auth: {:bearer, token})
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
  Posts a message to a channel (`chat.postMessage`), or with `thread_ts:` as
  a reply in a message's thread. Links in it are not unfurled: the message
  already says what they point at.
  """
  @spec post_message(String.t(), String.t(), %{text: String.t(), blocks: [map()]}, keyword()) ::
          {:ok, map()} | {:error, error()}
  def post_message(token, channel_id, %{text: text, blocks: blocks}, opts \\ []) do
    body =
      %{channel: channel_id, text: text, unfurl_links: false, unfurl_media: false}
      |> put_unless_empty(:blocks, blocks)
      |> put_unless_empty(:thread_ts, opts[:thread_ts])

    post("chat.postMessage", json: body, auth: {:bearer, token})
  end

  defp put_unless_empty(body, _key, value) when value in [nil, []], do: body
  defp put_unless_empty(body, key, value), do: Map.put(body, key, value)

  @doc """
  Previews links in a message (`chat.unfurl`). `body` names the message,
  as `channel` and `ts` or as `unfurl_id` and `source`, and carries either
  the `unfurls`, by URL, or `user_auth_required` and the blocks asking the
  person who posted the links to link their account.
  """
  @spec unfurl(String.t(), map()) :: {:ok, map()} | {:error, error()}
  def unfurl(token, body) do
    post("chat.unfurl", json: body, auth: {:bearer, token})
  end

  @doc """
  Answers an interaction through the `response_url` Slack sent with it,
  which needs no token. Only Slack's own URLs are posted to: the URL arrives
  in a request, and NervesHub does not send requests wherever a request
  tells it to.
  """
  @spec respond(String.t(), map()) :: {:ok, map()} | {:error, error()}
  def respond(response_url, message) do
    case URI.parse(response_url) do
      %URI{scheme: "https", host: "hooks.slack.com"} ->
        [method: :post, url: response_url, json: message, retry: false, receive_timeout: 10_000]
        |> Keyword.merge(Slack.config(:req_options) || [])
        |> Req.request()
        |> case do
          {:ok, %Req.Response{status: 200}} -> {:ok, %{}}
          {:ok, %Req.Response{status: status}} -> {:error, "HTTP #{status}"}
          {:error, exception} -> {:error, Exception.message(exception)}
        end

      _ ->
        {:error, "not a Slack response URL"}
    end
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
