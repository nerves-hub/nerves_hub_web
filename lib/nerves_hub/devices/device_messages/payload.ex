defmodule NervesHub.Devices.DeviceMessages.Payload do
  @moduledoc """
  Turns a message payload into the string stored in `device_messages`.

  Three things happen here, in order, and the order matters:

    1. **Redaction.** Payloads that cross a device link carry credentials —
       a presigned firmware URL is a bearer token for the firmware, and it
       is the single most sensitive thing the platform ever sends. Redaction
       runs before encoding so it reaches values nested inside update and
       archive payloads, not just the top level.
    2. **Encoding.** The result is JSON, so it renders and greps the same
       way regardless of which serializer the device negotiated.
    3. **Truncation.** A payload is capped so one oversized message cannot
       bloat a row. The original size is kept alongside, so the UI can say
       how much was dropped rather than silently showing a fragment.

  Console traffic never comes through here. It is raw terminal I/O and can
  contain anything a person typed at a prompt, including secrets, so only
  its size is recorded — see `NervesHub.Devices.DeviceMessages`.
  """

  alias NervesHub.Devices.DeviceMessages

  @default_max_bytes 8_192

  # Values under these keys are replaced outright. Nothing here is ever
  # useful for debugging what a device was told, and all of it is a
  # credential of some kind.
  @default_redacted_keys ~w(
    auth
    authorization
    password
    private_key
    secret
    token
  )

  # Values under these keys keep their scheme, host and path but lose the
  # query string, which is where presigned signatures live. Knowing a device
  # was pointed at a particular firmware object is the useful part; the
  # signature that lets anyone fetch it is not.
  @default_url_keys ~w(
    archive_url
    firmware_url
    url
  )

  @redacted "[redacted]"

  @doc """
  Encodes `payload` for storage.

  Returns `{encoded, original_byte_size, truncated?}`, where `original_byte_size`
  is the size after redaction but before truncation.
  """
  @spec encode(term()) :: {String.t(), non_neg_integer(), boolean()}
  def encode(payload) do
    encoded =
      payload
      |> redact()
      |> to_json()

    size = byte_size(encoded)
    max_bytes = max_bytes()

    if size > max_bytes do
      {binary_slice(encoded, 0, max_bytes), size, true}
    else
      {encoded, size, false}
    end
  end

  @doc """
  Replaces sensitive values anywhere in `payload`, at any depth.
  """
  @spec redact(term()) :: term()
  # A struct is normalised through its own JSON encoder before being walked, so
  # what gets redacted is exactly the set of fields the device receives. This is
  # not a detail: `NervesHub.Devices.UpdatePayload` is a struct, it derives an
  # encoder that whitelists a handful of fields, and it carries the presigned
  # `firmware_url`. Walking the raw struct would both miss that whitelist — the
  # loaded deployment group and its associations are not sent to the device and
  # have no business being stored — and, because a struct is a map, quietly skip
  # redaction entirely.
  def redact(%_{} = struct) do
    case Jason.encode(struct) do
      {:ok, encoded} -> encoded |> Jason.decode!() |> redact()
      {:error, _reason} -> inspect(struct)
    end
  end

  def redact(payload) when is_map(payload) do
    Map.new(payload, fn {key, value} -> {key, redact_pair(key, value)} end)
  end

  def redact(payload) when is_list(payload), do: Enum.map(payload, &redact/1)

  def redact(payload), do: payload

  defp redact_pair(key, value) do
    normalised = normalise_key(key)

    cond do
      normalised in redacted_keys() -> @redacted
      normalised in url_keys() -> redact_url(value)
      true -> redact(value)
    end
  end

  defp normalise_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalise_key(key) when is_binary(key), do: key
  defp normalise_key(key), do: inspect(key)

  # A URL keeps everything up to the query string. Anything that does not
  # parse as a URL is redacted outright rather than guessed at.
  defp redact_url(value) when is_binary(value) do
    case URI.new(value) do
      {:ok, %URI{query: nil} = uri} -> URI.to_string(uri)
      {:ok, %URI{} = uri} -> URI.to_string(%{uri | query: nil}) <> "?#{@redacted}"
      {:error, _part} -> @redacted
    end
  end

  defp redact_url(_value), do: @redacted

  # Payloads reaching here are already plain maps, lists and scalars, but a
  # device can send anything and an encoder failure must not lose the row.
  defp to_json(payload) do
    case Jason.encode(payload) do
      {:ok, encoded} -> encoded
      {:error, _reason} -> Jason.encode!(inspect(payload))
    end
  end

  defp max_bytes(), do: config(:max_payload_bytes, @default_max_bytes)

  defp redacted_keys(), do: config(:redacted_keys, @default_redacted_keys)

  defp url_keys(), do: config(:redacted_url_keys, @default_url_keys)

  defp config(key, default) do
    :nerves_hub
    |> Application.get_env(DeviceMessages, [])
    |> Keyword.get(key, default)
  end
end
