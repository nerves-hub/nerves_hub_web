defmodule NervesHub.Devices.AdvancedQuery.Parser do
  @moduledoc """
  Recursive-descent parser for the device list advanced query language.

      query      := orExpr
      orExpr     := andExpr (OR andExpr)*
      andExpr    := term (AND term)*
      term       := NOT term | "(" orExpr ")" | comparison
      comparison := COLUMN OP value

  Columns, operators, and values are validated against
  `NervesHub.Devices.AdvancedQuery.Schema` as the query is parsed, scoped to
  a product (since predefined values like platform/architecture/tags are
  product-specific).

  Produces an AST of:

      {:and, left, right}
      {:or, left, right}
      {:not, expr}
      {:comparison, column, operator, value}
  """

  alias NervesHub.Devices.AdvancedQuery.Lexer
  alias NervesHub.Devices.AdvancedQuery.Lexer.Token
  alias NervesHub.Devices.AdvancedQuery.Schema

  @type ast ::
          {:and, ast, ast}
          | {:or, ast, ast}
          | {:not, ast}
          | {:comparison, String.t(), String.t(), String.t()}

  @doc """
  Parses a raw query string into an AST, scoped to a product for value
  validation.
  """
  @spec parse(String.t(), pos_integer()) :: {:ok, ast} | {:error, String.t(), non_neg_integer()}
  def parse(input, product_id) do
    with {:ok, tokens} <- Lexer.tokenize(input) do
      case parse_or(tokens, product_id) do
        {:ok, ast, [%Token{type: :eof}]} -> {:ok, ast}
        {:ok, _ast, [%Token{position: position} | _]} -> {:error, "unexpected trailing input", position}
        {:error, message, position} -> {:error, message, position}
      end
    end
  end

  defp parse_or(tokens, product_id) do
    with {:ok, left, rest} <- parse_and(tokens, product_id) do
      parse_or_rest(left, rest, product_id)
    end
  end

  defp parse_or_rest(left, [%Token{type: :ident, value: value} | rest] = tokens, product_id) do
    if keyword(value) == :or do
      with {:ok, right, rest} <- parse_and(rest, product_id) do
        parse_or_rest({:or, left, right}, rest, product_id)
      end
    else
      {:ok, left, tokens}
    end
  end

  defp parse_or_rest(left, tokens, _product_id), do: {:ok, left, tokens}

  defp parse_and(tokens, product_id) do
    with {:ok, left, rest} <- parse_term(tokens, product_id) do
      parse_and_rest(left, rest, product_id)
    end
  end

  defp parse_and_rest(left, [%Token{type: :ident, value: value} | rest] = tokens, product_id) do
    if keyword(value) == :and do
      with {:ok, right, rest} <- parse_term(rest, product_id) do
        parse_and_rest({:and, left, right}, rest, product_id)
      end
    else
      {:ok, left, tokens}
    end
  end

  defp parse_and_rest(left, tokens, _product_id), do: {:ok, left, tokens}

  defp parse_term([%Token{type: :ident, value: value} | _] = tokens, product_id) do
    if keyword(value) == :not do
      [_ | rest] = tokens

      with {:ok, expr, rest} <- parse_term(rest, product_id) do
        {:ok, {:not, expr}, rest}
      end
    else
      parse_comparison(tokens, product_id)
    end
  end

  defp parse_term([%Token{type: :symbol, value: "("} | rest], product_id) do
    with {:ok, expr, rest} <- parse_or(rest, product_id) do
      case rest do
        [%Token{type: :symbol, value: ")"} | rest] -> {:ok, expr, rest}
        [%Token{position: position} | _] -> {:error, "expected closing parenthesis", position}
      end
    end
  end

  defp parse_term(tokens, product_id), do: parse_comparison(tokens, product_id)

  defp parse_comparison([%Token{type: :ident, value: column, position: position} | rest], product_id) do
    column = String.downcase(column)

    with :ok <- validate_column(column, position),
         {:ok, operator, rest} <- parse_operator(rest, column),
         {:ok, value, rest} <- parse_value(rest, column, operator, product_id) do
      {:ok, {:comparison, column, operator, value}, rest}
    end
  end

  defp parse_comparison([%Token{position: position} | _], _product_id) do
    {:error, "expected a column name", position}
  end

  @symbol_operators ["=", "!=", ">", ">=", "<", "<="]

  defp parse_operator([%Token{type: :symbol, value: operator, position: position} | rest], column)
       when operator in @symbol_operators do
    validate_operator(operator, column, position, rest)
  end

  defp parse_operator([%Token{type: :ident, value: value, position: position} | rest], column) do
    {operator, rest} = ident_operator(value, rest)
    validate_operator(operator, column, position, rest)
  end

  defp parse_operator([%Token{position: position} | _], _column) do
    {:error, "expected an operator", position}
  end

  # Two-word ident operators (in operator position, so the leading `not` of
  # "not like" is unambiguously part of the operator rather than the NOT keyword).
  @two_word_operators ["is not", "not like"]

  # Recognizes a two-word operator; otherwise the operator is the single ident
  # and the following token is left for the value.
  defp ident_operator(value, [%Token{type: :ident, value: next} | tail] = rest) do
    candidate = String.downcase(value) <> " " <> String.downcase(next)

    if candidate in @two_word_operators do
      {candidate, tail}
    else
      {String.downcase(value), rest}
    end
  end

  defp ident_operator(value, rest), do: {String.downcase(value), rest}

  defp validate_operator(operator, column, position, rest) do
    if Schema.operator?(column, operator) do
      {:ok, operator, rest}
    else
      {:error, "#{inspect(operator)} is not a valid operator for #{inspect(column)}", position}
    end
  end

  defp parse_value([%Token{type: type, value: value, position: position} | rest], column, operator, product_id)
       when type in [:string, :ident] do
    if Schema.value?(column, value, product_id) do
      {:ok, value, rest}
    else
      {:error, "#{inspect(value)} is not a valid value for #{inspect(column)} #{operator}", position}
    end
  end

  defp parse_value([%Token{position: position} | _], _column, _operator, _product_id) do
    {:error, "expected a value", position}
  end

  defp validate_column(column, position) do
    if Schema.column?(column) do
      :ok
    else
      {:error, "#{inspect(column)} is not a valid column", position}
    end
  end

  defp keyword(value) do
    case String.downcase(value) do
      "and" -> :and
      "or" -> :or
      "not" -> :not
      _ -> nil
    end
  end
end
