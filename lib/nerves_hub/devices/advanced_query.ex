defmodule NervesHub.Devices.AdvancedQuery do
  @moduledoc """
  Public API for the device list advanced query language: a small boolean
  expression grammar over a whitelisted set of columns
  (`NervesHub.Devices.AdvancedQuery.Schema`), used by the search bar on the
  devices list page.

  Deliberately kept separate from `NervesHub.Devices.DeviceFiltering` (the
  sidebar/basic search filters) so this can be tested and evolved in
  isolation.

  Input that doesn't look like a query expression at all (e.g. a pasted
  device identifier) is treated as a free-text search rather than an error -
  see `interpret/2`.
  """

  alias NervesHub.Devices.AdvancedQuery.Compiler
  alias NervesHub.Devices.AdvancedQuery.Parser
  alias NervesHub.Devices.AdvancedQuery.Schema

  @type ast :: Parser.ast()

  @doc "Parses a raw query string into an AST, scoped to a product for value validation."
  @spec parse(String.t(), pos_integer()) :: {:ok, ast} | {:error, String.t(), non_neg_integer()}
  def parse(input, product_id), do: Parser.parse(input, product_id)

  @doc """
  Interprets raw search input as either a query expression or free text.

  Input that parses is a query as usual. Input that fails to parse but still
  looks like an attempted query expression (starts with a whitelisted column,
  `not`, or `(`, or contains an operator symbol or quote) keeps its parse
  error, so typos in real queries surface instead of silently matching
  nothing. Anything else - a pasted device identifier, a tag, a firmware
  version - is treated as free text and rewritten to `search like "%input%"`,
  matching across the device's textual fields.

  Returns `{:ok, canonical_query, ast}` where `canonical_query` is the input
  itself for query expressions, or the rewritten `search like` form for free
  text - callers surface the rewritten form so users see the query their
  free text became.
  """
  @spec interpret(String.t(), pos_integer()) :: {:ok, String.t(), ast} | {:error, String.t(), non_neg_integer()}
  def interpret(input, product_id) when is_binary(input) do
    input = String.trim(input)

    case parse(input, product_id) do
      {:ok, ast} ->
        {:ok, input, ast}

      {:error, _message, _position} = error ->
        if query_attempt?(input) do
          error
        else
          free_text_query(input, product_id)
        end
    end
  end

  @doc """
  Applies a raw query string to a query as an additional `where` clause.

  Assumes the query already has a `latest_connection` named binding (see
  `NervesHub.Devices.common_filter_query/1`). Free-text input is applied via
  the `interpret/2` fallback; if the query string is blank or is an invalid
  query expression, the query is returned unchanged - invalid advanced
  queries don't affect the rest of the filter results.
  """
  @spec apply_to_query(Ecto.Query.t(), String.t() | nil, pos_integer()) :: Ecto.Query.t()
  def apply_to_query(query, nil, _product_id), do: query

  def apply_to_query(query, input, product_id) when is_binary(input) do
    case String.trim(input) do
      "" ->
        query

      input ->
        case interpret(input, product_id) do
          {:ok, _canonical, ast} -> Compiler.apply_query(query, ast)
          {:error, _message, _position} -> query
        end
    end
  end

  @doc """
  Whether a (valid) raw query references the given column anywhere in its
  expression. Used to let advanced queries take over filtering that the basic
  filters apply by default (e.g. excluding soft-deleted devices).
  """
  @spec references_column?(String.t() | nil, pos_integer(), String.t()) :: boolean()
  def references_column?(input, product_id, column) when is_binary(input) do
    case parse(input, product_id) do
      {:ok, ast} -> ast_references?(ast, column)
      {:error, _message, _position} -> false
    end
  end

  def references_column?(_input, _product_id, _column), do: false

  defp ast_references?({:and, left, right}, column), do: ast_references?(left, column) or ast_references?(right, column)

  defp ast_references?({:or, left, right}, column), do: ast_references?(left, column) or ast_references?(right, column)

  defp ast_references?({:not, expr}, column), do: ast_references?(expr, column)
  defp ast_references?({:comparison, col, _op, _value}, column), do: col == column

  # Whether input that failed to parse still reads as an attempted query expression
  # (whose error should surface rather than fall back to free text): it starts
  # the only ways a valid expression can - with a whitelisted column, the NOT
  # keyword, or an opening parenthesis - or it contains an operator symbol or
  # quoted string, the telltale shape of a query with a typo.
  defp query_attempt?(input) do
    first_word =
      input
      |> String.split(~r/[\s=!<>]/, parts: 2)
      |> hd()
      |> String.downcase()

    String.starts_with?(input, "(") or
      first_word == "not" or
      Schema.column?(first_word) or
      String.contains?(input, ["=", "<", ">", "\""])
  end

  # Free text is wrapped in a quoted string (escaped per the lexer's rules) and
  # surrounded with `%` wildcards so it matches as a case-insensitive substring.
  defp free_text_query(input, product_id) do
    escaped =
      input
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")

    query = ~s|search like "%#{escaped}%"|
    {:ok, ast} = parse(query, product_id)
    {:ok, query, ast}
  end
end
