defmodule NervesHub.Devices.AdvancedQuery.Lexer do
  @moduledoc """
  Tokenizer for the device list advanced query language.

  The lexer is deliberately context-free: it doesn't know which bare words
  are keywords (`and`/`or`/`not`), column names, or operator words
  (`contains`/`not_contains`) - that's decided by `NervesHub.Devices.AdvancedQuery.Parser`
  based on grammar position. This keeps the lexer simple and reusable.
  """

  defmodule Token do
    @moduledoc false
    @enforce_keys [:type, :value, :position]
    defstruct [:position, :type, :value]

    @type t :: %__MODULE__{
            type: :ident | :string | :symbol | :eof,
            value: String.t(),
            position: non_neg_integer()
          }
  end

  # Multi-character symbols must precede their single-character prefixes so the
  # longest match wins (e.g. ">=" before ">").
  @symbols ["!=", ">=", "<=", "=", ">", "<", "(", ")"]

  @doc """
  Tokenizes a query string.

  Returns `{:ok, [%Token{}, ...]}` (always ending in an `:eof` token) or
  `{:error, message, position}`.
  """
  @spec tokenize(String.t()) :: {:ok, [Token.t()]} | {:error, String.t(), non_neg_integer()}
  def tokenize(input) when is_binary(input) do
    do_tokenize(input, 0, [])
  end

  defp do_tokenize(<<>>, position, acc) do
    {:ok, Enum.reverse([%Token{type: :eof, value: "", position: position} | acc])}
  end

  defp do_tokenize(<<char, rest::binary>>, position, acc) when char in [?\s, ?\t, ?\n, ?\r] do
    do_tokenize(rest, position + 1, acc)
  end

  defp do_tokenize(<<?", rest::binary>>, position, acc) do
    case consume_string(rest, position + 1, []) do
      {:ok, value, remaining, end_position} ->
        token = %Token{type: :string, value: value, position: position}
        do_tokenize(remaining, end_position, [token | acc])

      {:error, message} ->
        {:error, message, position}
    end
  end

  defp do_tokenize(input, position, acc) do
    cond do
      symbol = Enum.find(@symbols, &String.starts_with?(input, &1)) ->
        rest = binary_part(input, byte_size(symbol), byte_size(input) - byte_size(symbol))
        token = %Token{type: :symbol, value: symbol, position: position}
        do_tokenize(rest, position + byte_size(symbol), [token | acc])

      ident_char?(input) ->
        {value, rest} = consume_ident(input, "")
        token = %Token{type: :ident, value: value, position: position}
        do_tokenize(rest, position + byte_size(value), [token | acc])

      true ->
        <<char::utf8, _::binary>> = input
        {:error, "unexpected character #{inspect(<<char::utf8>>)}", position}
    end
  end

  defp consume_string(<<?", rest::binary>>, position, acc) do
    {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary(), rest, position + 1}
  end

  defp consume_string(<<?\\, ?", rest::binary>>, position, acc) do
    consume_string(rest, position + 2, [?" | acc])
  end

  defp consume_string(<<?\\, ?\\, rest::binary>>, position, acc) do
    consume_string(rest, position + 2, [?\\ | acc])
  end

  defp consume_string(<<char, rest::binary>>, position, acc) do
    consume_string(rest, position + 1, [char | acc])
  end

  defp consume_string(<<>>, _position, _acc) do
    {:error, "unterminated string"}
  end

  defp ident_char?(<<char, _::binary>>) do
    # `:` is allowed so the `metric:<key>` column syntax tokenizes as one ident.
    (char >= ?a and char <= ?z) or
      (char >= ?A and char <= ?Z) or
      (char >= ?0 and char <= ?9) or
      char in [?_, ?-, ?., ?:]
  end

  defp ident_char?(<<>>), do: false

  defp consume_ident(input, acc) do
    if ident_char?(input) do
      <<char, rest::binary>> = input
      consume_ident(rest, acc <> <<char>>)
    else
      {acc, input}
    end
  end
end
