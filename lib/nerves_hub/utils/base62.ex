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

  @decode_chars @chars |> Enum.with_index() |> Map.new()
  @encode_chars List.to_tuple(@chars)

  @spec bin_to_integer(binary()) :: integer()
  def bin_to_integer(bin) do
    list_of_bytes = for <<byte::8 <- bin>>, do: byte

    Integer.undigits(list_of_bytes, 256)
  end

  @spec encode(binary() | integer()) :: binary()
  def encode(""), do: ""

  def encode(byte_data) when is_bitstring(byte_data) do
    byte_data
    # convert it into an integer
    |> bin_to_integer()
    # uses the integer version of encode now
    |> encode()
  end

  def encode(integer_data) when is_integer(integer_data) do
    cache = @encode_chars

    # get mod 62 numbers into a list
    integer_data |> Integer.digits(62) |> Enum.into("", fn data -> elem(cache, data) end)
  end

  @spec decode(binary()) :: {:ok, binary()} | :error
  def decode(string_data) do
    {:ok, decode!(string_data)}
  rescue
    _ -> :error
  end

  @spec decode!(binary()) :: binary()
  def decode!(""), do: <<>>

  def decode!(string_data) when is_binary(string_data) do
    cache = @decode_chars

    string_data
    |> String.graphemes()
    |> Enum.map(fn char -> cache[char] end)
    |> Integer.undigits(62)
    |> Integer.digits(256)
    |> Enum.reduce(<<>>, fn number, acc ->
      acc <> <<number>>
    end)
  end
end
