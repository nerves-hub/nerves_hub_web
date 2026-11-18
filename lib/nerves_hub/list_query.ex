defmodule NervesHub.ListQuery do
  @moduledoc """
  Helpers the contexts share when they turn a list page's params into a query:
  escaping a search for `ilike`, and reading a page number or size.
  """

  @doc """
  Escapes `%`, `_` and `\\` in a search, so `ilike` matches them literally.

  `%` and `_` are wildcards to `ilike`, and the things people search for hold
  them by accident: a version with an underscore, a device logging "100%".

      iex> NervesHub.ListQuery.escape_like("1.0_rc%")
      "1.0\\\\_rc\\\\%"
  """
  @spec escape_like(String.t()) :: String.t()
  def escape_like(search) do
    String.replace(search, ~r/([\\%_])/, "\\\\\\1")
  end

  @doc """
  A page number or size from params: a positive integer, or the text of one,
  as it is. Anything else, such as `"0"`, `"-1"` or `"abc"`, is `default`.

      iex> NervesHub.ListQuery.positive_integer("3", 1)
      3

      iex> NervesHub.ListQuery.positive_integer("0", 1)
      1
  """
  @spec positive_integer(term(), pos_integer()) :: pos_integer()
  def positive_integer(value, _default) when is_integer(value) and value > 0, do: value

  def positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _ -> default
    end
  end

  def positive_integer(_value, default), do: default
end
