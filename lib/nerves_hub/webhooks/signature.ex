defmodule NervesHub.Webhooks.Signature do
  @moduledoc """
  Signs webhook deliveries the way the Standard Webhooks specification
  describes (https://www.standardwebhooks.com).

  Following an existing specification rather than inventing a scheme means a
  receiver can verify deliveries with an off-the-shelf library in most
  languages, instead of reimplementing ours from documentation.

  A delivery carries three headers:

    * `webhook-id` — the event's id, the same on every retry, so a receiver can
      use it to ignore a delivery it has already processed.
    * `webhook-timestamp` — when this attempt was sent, in Unix seconds, so a
      receiver can refuse a replayed request.
    * `webhook-signature` — `v1,` and the base64 HMAC-SHA256 of
      `"<webhook-id>.<webhook-timestamp>.<body>"`, keyed with the secret.

  The secret is `whsec_` followed by 32 random bytes in base64. The HMAC key is
  the decoded bytes, not the string, which is what the specification's
  libraries expect.
  """

  @prefix "whsec_"
  @secret_bytes 32

  @doc "A new signing secret."
  @spec generate_secret() :: String.t()
  def generate_secret() do
    @prefix <> Base.encode64(:crypto.strong_rand_bytes(@secret_bytes))
  end

  @doc """
  The `webhook-signature` header value for one delivery attempt.
  """
  @spec sign(secret :: String.t(), id :: String.t(), timestamp :: integer(), body :: binary()) :: String.t()
  def sign(secret, id, timestamp, body) do
    mac = :crypto.mac(:hmac, :sha256, key(secret), "#{id}.#{timestamp}.#{body}")

    "v1," <> Base.encode64(mac)
  end

  @doc """
  Whether `signature_header` holds a valid signature for the delivery.

  The header may list several space-separated signatures, as the
  specification allows during a secret rotation; any one matching is enough.
  This is what a receiver does, and lives here so the tests check signing
  against verification rather than against a copy of `sign/4`.
  """
  @spec verify(String.t(), String.t(), integer() | String.t(), binary(), String.t()) :: boolean()
  def verify(secret, id, timestamp, body, signature_header) do
    expected = sign(secret, id, timestamp, body)

    signature_header
    |> String.split(" ", trim: true)
    |> Enum.any?(&Plug.Crypto.secure_compare(&1, expected))
  end

  defp key(@prefix <> encoded), do: Base.decode64!(encoded)
end
