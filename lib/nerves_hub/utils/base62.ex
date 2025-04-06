defmodule NervesHub.Utils.Base62 do
  @moduledoc """
  Provides functions for encoding and decoding data using the Base62 encoding scheme.

  Base62 is a binary-to-text encoding scheme that represents binary data in an ASCII string format.
  It uses a set of 62 characters (0-9, a-z, A-Z) to represent binary data in a way
  that is safe for use in URLs and other contexts where certain characters may be reserved or have special meaning.

  This module provides functions for encoding and decoding binary data or integers
  using the Base62 encoding scheme.
  The `encode/1` and `decode!/1` functions are the primary entry points for encoding and decoding data, respectively.

  Example usage:

      ```
      iex> Base62.encode("hello world")
      "AAwf93rvy4aWQVw"
      iex> Base62.decode!("AAwf93rvy4aWQVw")
      "hello world"
      ```

  Heavily inspired by https://github.com/tt67wq/lib-ecto/blob/master/lib/lib_ecto/base62/base62.ex
  """

  @chars String.graphemes("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

  @spec encode(binary() | integer()) :: binary()
  def encode(""), do: ""

  def encode(bin) when is_binary(bin) do
    bin
    |> :crypto.bytes_to_integer()
    |> encode()
  end

  def encode(int) when is_integer(int) do
    for n <- Integer.digits(int, 62), into: "", do: mod_val_to_char(n)
  end

  for {char, i} <- Enum.with_index(@chars) do
    defp mod_val_to_char(unquote(i)), do: unquote(char)
  end

  @spec decode!(binary()) :: binary()
  def decode!(""), do: ""

  def decode!(bin) when is_binary(bin) do
    bin
    |> chars_to_mod_vals!()
    |> Integer.undigits(62)
    |> Integer.digits(256)
    |> :binary.list_to_bin()
  end

  @spec decode(binary()) :: {:ok, binary()} | {:error, ArgumentError.t()}
  def decode(bin) do
    {:ok, decode!(bin)}
  rescue
    exception -> {:error, exception}
  end

  defp chars_to_mod_vals!(bin, mod_vals \\ [])
  defp chars_to_mod_vals!(<<>>, mod_vals), do: Enum.reverse(mod_vals)

  for {char, i} <- Enum.with_index(@chars) do
    defp chars_to_mod_vals!(<<unquote(char), rem::binary>>, mod_vals),
      do: chars_to_mod_vals!(rem, [unquote(i) | mod_vals])
  end

  defp chars_to_mod_vals!(<<byte, _::binary>>, mod_vals) do
    msg =
      "non-alphabet character found at pos #{length(mod_vals) + 1}: #{inspect(<<byte>>, binaries: :as_strings)} (byte #{byte})"

    raise ArgumentError, msg
  end
end
