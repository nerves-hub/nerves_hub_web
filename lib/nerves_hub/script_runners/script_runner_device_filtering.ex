defmodule NervesHub.ScriptRunners.ScriptRunnerDeviceFiltering do
  @moduledoc """
  Filtering and sorting for one run's device results.

  Separate from `NervesHub.ScriptRunners.ScriptRunnerFiltering`, which filters the
  runs themselves. These queries are always scoped to a single run and join
  `devices`, because the only thing worth searching by is the device's identifier
  — the result row has no name of its own.
  """
  import Ecto.Query

  alias NervesHub.ScriptRunners.ScriptRunnerDevice

  @spec build_filters(Ecto.Query.t(), %{optional(atom) => String.t()}) :: Ecto.Query.t()
  def build_filters(query, filters) do
    Enum.reduce(filters, query, fn {key, value}, query ->
      filter(query, filters, key, value)
    end)
  end

  @spec filter(Ecto.Query.t(), %{optional(atom) => String.t()}, atom, String.t()) :: Ecto.Query.t()
  def filter(query, filters, key, value)

  # Filter values are empty strings as default, they should be ignored.
  def filter(query, _filters, _key, "") do
    query
  end

  def filter(query, _filters, :identifier, value) do
    where(query, [device: d], ilike(d.identifier, ^"%#{value}%"))
  end

  # The value arrives from a query string, so it is matched against the known
  # statuses rather than converted: an unrecognised one is ignored, the same as any
  # other unusable filter value, instead of raising on a stale bookmarked URL.
  def filter(query, _filters, :status, value) do
    case Enum.find(ScriptRunnerDevice.statuses(), &(to_string(&1) == value)) do
      nil -> query
      status -> where(query, [srd], srd.status == ^status)
    end
  end

  # Ignore any undefined filter, so a stale bookmarked URL does not 500.
  def filter(query, _filters, _key, _value) do
    query
  end

  @doc """
  Sort a run's device results.

  Identifier lives on the joined device rather than the result row, so it is
  ordered through the named binding. Status is ordered by its string value, which
  is not the lifecycle order — `completed` before `failed` before `pending` — but
  is what a person clicking the column twice expects: the same statuses grouped
  together, one way or the other.
  """
  @spec sort(Ecto.Query.t(), {atom(), atom()}) :: Ecto.Query.t()
  def sort(query, {direction, :identifier}) do
    order_by(query, [device: d], [{^direction, d.identifier}])
  end

  def sort(query, {direction, field}) do
    # A tiebreak, so paging through rows that share a status is stable.
    query
    |> order_by([srd], [{^direction, field(srd, ^field)}])
    |> order_by([device: d], asc: d.identifier)
  end
end
