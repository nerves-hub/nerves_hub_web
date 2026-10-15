defmodule NervesHub.Integrations.Slack.Signature do
  @moduledoc """
  Checks that a request came from Slack.

  Slack signs each request it sends (events, and later interactions and
  slash commands) with the app's signing secret: `X-Slack-Signature` is
  `v0=` and the hex HMAC-SHA256 of `v0:<timestamp>:<raw body>`, with the
  timestamp from `X-Slack-Request-Timestamp`. A request more than five
  minutes old is refused, so a captured request cannot be replayed later.
  """

  @max_age_seconds 300

  @doc "The signature Slack sends for `body` sent at `timestamp`."
  @spec sign(String.t(), String.t(), binary()) :: String.t()
  def sign(signing_secret, timestamp, body) do
    mac = :crypto.mac(:hmac, :sha256, signing_secret, "v0:#{timestamp}:#{body}")
    "v0=" <> Base.encode16(mac, case: :lower)
  end

  @doc """
  Whether `signature` is Slack's signature of `body` at `timestamp`, and
  `timestamp` is within five minutes of `now` (Unix seconds).
  """
  @spec verify(String.t(), String.t(), binary(), String.t(), integer()) :: :ok | {:error, :stale | :invalid}
  def verify(signing_secret, timestamp, body, signature, now \\ System.os_time(:second)) do
    case Integer.parse(timestamp) do
      {sent_at, ""} when abs(now - sent_at) <= @max_age_seconds ->
        if Plug.Crypto.secure_compare(sign(signing_secret, timestamp, body), signature) do
          :ok
        else
          {:error, :invalid}
        end

      {_sent_at, ""} ->
        {:error, :stale}

      _not_a_timestamp ->
        {:error, :invalid}
    end
  end
end
