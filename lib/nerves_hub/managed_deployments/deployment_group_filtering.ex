defmodule NervesHub.ManagedDeployments.DeploymentGroupFiltering do
  @moduledoc """
  Encapsulates all deployment group filtering and sorting logic
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

  def filter(query, _filters, :name, value) do
    where(query, [deployment_group: dg], ilike(dg.name, ^"%#{value}%"))
  end

  def filter(query, _filters, :platform, value) do
    where(query, [firmware: f], f.platform == ^value)
  end

  def filter(query, _filters, :architecture, value) do
    where(query, [firmware: f], f.architecture == ^value)
  end

  def filter(query, _filters, :search, value) when is_binary(value) and value != "" do
    search_term = "%#{value}%"

    query
    |> where(
      [deployment_group: dg, firmware: f],
      ilike(dg.name, ^search_term) or
        ilike(f.platform, ^search_term) or
        ilike(f.architecture, ^search_term) or
        ilike(fragment(" COALESCE(?->>'tags', '')", dg.conditions), ^search_term)
    )
  end

  # Ignore any undefined filter.
  # This will prevent error 500 responses on deprecated saved bookmarks etc.
  def filter(query, _filters, _key, _value) do
    query
  end

  @spec sort(Ecto.Query.t(), {atom(), atom()}) :: Ecto.Query.t()
  def sort(query, {direction, :platform}) do
    order_by(query, [firmware: f], {^direction, f.platform})
  end

  def sort(query, {direction, :architecture}) do
    order_by(query, [firmware: f], {^direction, f.architecture})
  end

  def sort(query, {direction, :device_count}) do
    order_by(query, [device_count: dev], {^direction, dev.device_count})
  end

  def sort(query, {direction, :firmware_version}) do
    order_by(query, [firmware: f], {^direction, f.version})
  end

  def sort(query, sort), do: order_by(query, ^sort)
end
