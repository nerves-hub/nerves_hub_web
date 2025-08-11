defmodule NervesHub.Scripts.ScriptFiltering do
  @moduledoc """
  Encapsulates all script filtering and sorting logic
  """
  import Ecto.Query

  alias NervesHub.Types.Tag

  @spec build_filters(Ecto.Query.t(), %{optional(atom) => String.t()}) :: Ecto.Query.t()
  def build_filters(query, filters) do
    Enum.reduce(filters, query, fn {key, value}, query ->
      filter(query, filters, key, value)
    end)
  end

  @spec filter(Ecto.Query.t(), %{optional(atom) => String.t()}, atom, String.t()) ::
          Ecto.Query.t()
  def filter(query, filters, key, value)

  # Filter values are empty strings as default,
  # they should be ignored.
  def filter(query, _filters, _key, "") do
    query
  end

  def filter(query, _filters, :name, value) do
    where(query, [s], ilike(s.name, ^"%#{value}%"))
  end

  def filter(query, _filters, :tags, value) do
    case Tag.cast(value) do
      {:ok, tags} ->
        Enum.reduce(tags, query, fn tag, query ->
          where(
            query,
            [s],
            fragment("string_array_to_string(?, ' ', ' ') ILIKE ?", s.tags, ^"%#{tag}%")
          )
        end)

      {:error, _} ->
        query
    end
  end

  # Ignore any undefined filter.
  # This will prevent error 500 responses on deprecated saved bookmarks etc.
  def filter(query, _filters, _key, _value) do
    query
  end

  @spec sort(Ecto.Query.t(), {atom(), atom()}) :: Ecto.Query.t()
  def sort(query, sort), do: order_by(query, ^sort)
end
