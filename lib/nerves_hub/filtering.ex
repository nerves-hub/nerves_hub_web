defmodule NervesHub.Filtering do
  @moduledoc """
  Common filtering functionality for NervesHub resources.
  """
  import Ecto.Query

  alias NervesHub.Devices.AdvancedQuery
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceFiltering
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentGroupFiltering
  alias NervesHub.Products.Product
  alias NervesHub.Scripts.Script
  alias NervesHub.Scripts.ScriptFiltering

  @doc """
  Common filter function that can be used across different resources.

  ## Parameters
    - base_query: The initial Ecto query to build upon
    - product: The product to filter by
    - opts: Map of options maybe including:
      - sort: Tuple of {direction, field} for sorting
      - filters: Map of filters to apply
      - pagination: Map of pagination options

  ## Returns
    A tuple containing:
    - List of entries matching the query
    - Flop metadata containing pagination information
  """
  @spec filter(Ecto.Query.t(), Product.t(), map()) ::
          {[Device.t()] | [DeploymentGroup.t()] | [Script.t()], Flop.Meta.t()}
  def filter(base_query, product, opts \\ %{}) do
    pagination = Map.get(opts, :pagination, %{})

    flop = %Flop{
      page: Map.get(pagination, :page, 1),
      page_size: Map.get(pagination, :page_size, 25)
    }

    filter_query(base_query, product, opts)
    |> Flop.run(flop)
  end

  @spec filter_query(Ecto.Query.t(), Product.t(), map()) :: Ecto.Query.t()
  def filter_query(base_query, product, opts \\ %{}) do
    opts = Map.reject(opts, fn {_key, val} -> is_nil(val) end)

    sorting = Map.get(opts, :sort, {:asc, :name})
    filters = Map.get(opts, :filters, %{})

    base_query
    |> where([q], q.product_id == ^product.id)
    |> filter_and_sort(base_query.from, sorting, filters, product.id)
  end

  defp filter_and_sort(query, %{source: {_, Device}}, sorting_opts, filter_opts, product_id) do
    advanced_query = Map.get(filter_opts, :advanced_query)

    # When the advanced query checks the `deleted` column, let it control whether
    # soft-deleted devices appear instead of the basic filters' default exclusion
    # (otherwise `deleted = "true"` would be AND-ed against `deleted_at IS NULL`).
    filter_opts =
      if AdvancedQuery.references_column?(advanced_query, product_id, "deleted") do
        Map.delete(filter_opts, :display_deleted)
      else
        filter_opts
      end

    query
    |> DeviceFiltering.sort(sorting_opts)
    |> DeviceFiltering.build_filters(filter_opts)
    |> AdvancedQuery.apply_to_query(advanced_query, product_id)
  end

  defp filter_and_sort(query, %{source: {_, DeploymentGroup}}, sorting_opts, filter_opts, _product_id) do
    query
    |> DeploymentGroupFiltering.sort(sorting_opts)
    |> DeploymentGroupFiltering.build_filters(filter_opts)
  end

  defp filter_and_sort(query, %{source: {_, Script}}, sorting_opts, filter_opts, _product_id) do
    query
    |> ScriptFiltering.sort(sorting_opts)
    |> ScriptFiltering.build_filters(filter_opts)
  end
end
