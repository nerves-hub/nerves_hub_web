defimpl Jason.Encoder, for: OrderedCollections.SortedMap do
  @moduledoc """
  Encodes a `SortedMap` as a JSON object, preserving sorted key order.

  `SortedMap` implements `Enumerable` and yields `{key, value}` pairs in
  sorted-key order, so we iterate it directly and build the object by hand,
  reusing Jason's own helpers for keys and values. Converting to a plain map
  first would discard the ordering, which defeats the purpose of a SortedMap.
  """
  alias Jason.Encode

  def encode(sorted_map, opts) do
    sorted_map
    |> Enum.map(fn {key, value} ->
      [Encode.string(to_json_key(key), opts), ?:, Encode.value(value, opts)]
    end)
    |> case do
      [] -> "{}"
      pairs -> ["{", Enum.intersperse(pairs, ?,), "}"]
    end
  end

  # JSON object keys must be strings; mirror how Jason coerces map keys.
  defp to_json_key(key) when is_binary(key), do: key
  defp to_json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp to_json_key(key) when is_integer(key), do: Integer.to_string(key)

  defp to_json_key(key) do
    raise Jason.EncodeError, "unsupported JSON object key: #{inspect(key)}"
  end
end
