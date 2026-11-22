defmodule NervesHub.Devices.BulkImport do
  @moduledoc """
  Reads the device manifests `POST .../devices/import` accepts, without raising.

  A problem with the whole manifest (an unknown format, a body that isn't a
  non-empty list) fails the manifest; a problem with one entry fails only that
  entry, so the caller can refuse the manifest or count the entry as failed and
  carry on. Each problem is a `{path, message}` pair naming where it is, such as
  `"format"`, `"entries"` or `"entries[3].payload"`, counting entries from 0. A
  certificate that decodes but isn't valid X.509 is not a parse problem: the
  entry comes back with `pem: {:error, _}` and fails when the device is created.
  """

  @default_format "microchip_trust_and_go"
  @formats [@default_format]

  @type problem :: {path :: String.t(), message :: String.t()}
  @type entry :: %{device_identifier: String.t(), pem: {:ok, String.t()} | {:error, term()}}
  @type entry_result :: {:ok, entry()} | {:error, problem()}

  @doc "The format a manifest is read as when the request doesn't name one."
  @spec default_format() :: String.t()
  def default_format(), do: @default_format

  @doc "The manifest formats NervesHub can read."
  @spec formats() :: [String.t()]
  def formats(), do: @formats

  @doc """
  Parse a manifest given as JSON. See `parse/2`.
  """
  @spec parse_file(String.t() | nil, binary()) :: {:ok, [entry_result()]} | {:error, [problem()]}
  def parse_file(format, json_payload) when is_binary(json_payload) do
    case JSON.decode(json_payload) do
      {:ok, entries} -> parse(format, entries)
      {:error, _} -> {:error, [{"entries", "must be a JSON array of manifest entries"}]}
    end
  end

  @doc """
  Parse a manifest that has already been decoded from JSON.

  Returns `{:ok, results}` with one result per entry, in order, or
  `{:error, problems}` when the manifest can't be read at all.
  """
  @spec parse(String.t() | nil, term()) :: {:ok, [entry_result()]} | {:error, [problem()]}
  def parse(format, _entries) when format not in @formats do
    {:error, [{"format", "must be one of: #{Enum.join(@formats, ", ")}"}]}
  end

  def parse(_format, []) do
    {:error, [{"entries", "must have at least one entry"}]}
  end

  def parse(format, entries) when is_list(entries) do
    results =
      entries
      |> Enum.with_index()
      |> Enum.map(fn {entry, index} ->
        case parse_entry(format, entry) do
          {:ok, entry} -> {:ok, entry}
          {:error, {path, message}} -> {:error, {entry_path(index, path), message}}
        end
      end)

    {:ok, results}
  end

  def parse(_format, _entries) do
    {:error, [{"entries", "must be a JSON array of manifest entries"}]}
  end

  @doc """
  Parse a manifest, refusing it if any entry can't be read.

  Returns the entries when every one of them can be read, or every problem
  found, so a client can fix them all at once.
  """
  @spec validate(String.t() | nil, term()) :: {:ok, [entry()]} | {:error, [problem()]}
  def validate(format, entries) do
    parsed = if is_binary(entries), do: parse_file(format, entries), else: parse(format, entries)

    with {:ok, results} <- parsed do
      case Enum.split_with(results, &match?({:ok, _}, &1)) do
        {ok, []} -> {:ok, Enum.map(ok, fn {:ok, entry} -> entry end)}
        {_ok, errors} -> {:error, Enum.map(errors, fn {:error, problem} -> problem end)}
      end
    end
  end

  defp entry_path(index, nil), do: "entries[#{index}]"
  defp entry_path(index, path), do: "entries[#{index}].#{path}"

  defp parse_entry("microchip_trust_and_go", entry) do
    with {:ok, identifier} <- tng_identifier(entry),
         {:ok, payload} <- tng_payload(entry),
         {:ok, der} <- tng_certificate(payload) do
      {:ok, %{device_identifier: identifier, pem: to_pem(der)}}
    end
  end

  defp tng_identifier(%{"header" => %{"uniqueId" => id}}) when is_binary(id) and id != "", do: {:ok, id}
  defp tng_identifier(%{"header" => %{}}), do: {:error, {"header.uniqueId", "must be a non-empty string"}}
  defp tng_identifier(%{"header" => _}), do: {:error, {"header", "must be an object"}}
  defp tng_identifier(%{}), do: {:error, {"header", "is required"}}
  defp tng_identifier(_), do: {:error, {nil, "must be an object"}}

  defp tng_payload(%{"payload" => payload}) when is_binary(payload) do
    with {:decode, {:ok, json}} <- {:decode, Base.decode64(payload, padding: false)},
         {:ok, %{} = decoded} <- JSON.decode(json) do
      {:ok, decoded}
    else
      {:decode, :error} -> {:error, {"payload", "is not valid base64"}}
      _ -> {:error, {"payload", "does not decode to a JSON object"}}
    end
  end

  defp tng_payload(%{"payload" => _}), do: {:error, {"payload", "must be a string"}}
  defp tng_payload(_), do: {:error, {"payload", "is required"}}

  defp tng_certificate(%{"publicKeySet" => %{"keys" => keys}}) when is_list(keys) do
    case Enum.find(keys, &(is_map(&1) and Map.has_key?(&1, "x5c"))) do
      %{"x5c" => [cert | _]} when is_binary(cert) ->
        case Base.decode64(cert, padding: false) do
          {:ok, der} -> {:ok, der}
          :error -> {:error, {"payload.publicKeySet.keys.x5c[0]", "is not valid base64"}}
        end

      %{"x5c" => _} ->
        {:error, {"payload.publicKeySet.keys.x5c", "must be a non-empty list of base64-encoded certificates"}}

      nil ->
        {:error, {"payload.publicKeySet.keys", "has no key with an x5c certificate chain"}}
    end
  end

  defp tng_certificate(_), do: {:error, {"payload.publicKeySet.keys", "must be a list"}}

  defp to_pem(der) do
    case X509.Certificate.from_der(der) do
      {:ok, cert} -> {:ok, X509.Certificate.to_pem(cert)}
      {:error, _} = error -> error
    end
  end
end
