defmodule NervesHub.ScriptRunners.ScriptRunnerFiltering do
  @moduledoc """
  Encapsulates all script runner filtering and sorting logic
  """
  import Ecto.Query

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

  # Name first, since that is what the listing shows, but the code is searched
  # too -- "which run was it that called reboot?" is a question people ask when
  # they cannot remember what they named it.
  def filter(query, _filters, :search, value) do
    search_term = "%#{value}%"

    where(query, [sr], ilike(sr.name, ^search_term) or ilike(sr.text, ^search_term))
  end

  # Ignore any undefined filter.
  # This will prevent error 500 responses on deprecated saved bookmarks etc.
  def filter(query, _filters, _key, _value) do
    query
  end

  @spec sort(Ecto.Query.t(), {atom(), atom()}) :: Ecto.Query.t()
  def sort(query, sort), do: order_by(query, ^sort)
end
