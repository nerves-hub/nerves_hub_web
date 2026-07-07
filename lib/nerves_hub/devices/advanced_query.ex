defmodule NervesHub.Devices.AdvancedQuery do
  @moduledoc """
  Public API for the device list advanced query language: a small boolean
  expression grammar over a whitelisted set of columns
  (`NervesHub.Devices.AdvancedQuery.Schema`), used by the search bar on the
  devices list page.

  Deliberately kept separate from `NervesHub.Devices.DeviceFiltering` (the
  sidebar/basic search filters) so this can be tested and evolved in
  isolation.
  """

  alias NervesHub.Devices.AdvancedQuery.Compiler
  alias NervesHub.Devices.AdvancedQuery.Parser

  @type ast :: Parser.ast()

  @doc "Parses a raw query string into an AST, scoped to a product for value validation."
  @spec parse(String.t(), pos_integer()) :: {:ok, ast} | {:error, String.t(), non_neg_integer()}
  def parse(input, product_id), do: Parser.parse(input, product_id)

  @doc """
  Applies a raw query string to a query as an additional `where` clause.

  Assumes the query already has a `latest_connection` named binding (see
  `NervesHub.Devices.common_filter_query/1`). If the query string is blank
  or fails to parse, the query is returned unchanged - invalid advanced
  queries don't affect the rest of the filter results.
  """
  @spec apply_to_query(Ecto.Query.t(), String.t() | nil, pos_integer()) :: Ecto.Query.t()
  def apply_to_query(query, nil, _product_id), do: query
  def apply_to_query(query, "", _product_id), do: query

  def apply_to_query(query, input, product_id) when is_binary(input) do
    case parse(input, product_id) do
      {:ok, ast} -> Compiler.apply_query(query, ast)
      {:error, _message, _position} -> query
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
end
