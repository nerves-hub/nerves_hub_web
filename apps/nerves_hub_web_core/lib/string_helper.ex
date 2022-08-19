defmodule StringHelper do
  @spec to_integer(nil | binary() | integer(), integer() | nil) :: integer() | nil
  def to_integer(_string, _error_value \\ nil)

  def to_integer(not_a_string, _error_value) when is_integer(not_a_string),
    do: not_a_string

  def to_integer(string, error_value) when is_binary(string) do
    string
    |> Float.parse()
    |> case do
      {float_value, _remainder} -> round(float_value)
      :error -> error_value
    end
  end

  def to_integer(_, error_value), do: error_value
end
