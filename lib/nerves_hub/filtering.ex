defmodule NervesHub.Filtering do
  @moduledoc """
  Common filtering functionality for NervesHub resources.
  """
  import Ecto.Query

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
    opts = Map.reject(opts, fn {_key, val} -> is_nil(val) end)

    sorting = Map.get(opts, :sort, {:asc, :name})
    filters = Map.get(opts, :filters, %{})
    pagination = Map.get(opts, :pagination, %{})

    flop = %Flop{
      page: Map.get(pagination, :page, 1),
      page_size: Map.get(pagination, :page_size, 25)
    }

    base_query
    |> where([q], q.product_id == ^product.id)
    |> filter_and_sort(base_query.from, sorting, filters)
    |> Flop.run(flop)
  end

  defp filter_and_sort(query, %{source: {_, Device}}, sorting_opts, filter_opts) do
    query
    |> DeviceFiltering.sort(sorting_opts)
    |> DeviceFiltering.build_filters(filter_opts)
  end

  defp filter_and_sort(query, %{source: {_, DeploymentGroup}}, sorting_opts, filter_opts) do
    query
    |> DeploymentGroupFiltering.sort(sorting_opts)
    |> DeploymentGroupFiltering.build_filters(filter_opts)
  end

  defp filter_and_sort(query, %{source: {_, Script}}, sorting_opts, filter_opts) do
    query
    |> ScriptFiltering.sort(sorting_opts)
    |> ScriptFiltering.build_filters(filter_opts)
  end
end
