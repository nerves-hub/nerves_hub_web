defmodule NervesHub.Filtering do
  @moduledoc """
  Common filtering functionality for NervesHub resources.
  """
  alias NervesHub.Devices.Filtering, as: DevicesFiltering
  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments.Filtering, as: DeploymentsFiltering
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Products.Product
  alias NervesHub.Scripts.Filtering, as: ScriptsFiltering
  alias NervesHub.Scripts.Script

  import Ecto.Query

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
          {[%Device{}] | [%DeploymentGroup{}] | [%Script{}], Flop.Meta.t()}
  def filter(base_query, product, opts \\ %{}) do
    %{filter_builder: filter_builder, sorter: sorter} = filter_config(base_query.from)

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
    |> filter_builder.(filters)
    |> sorter.(sorting)
    |> Flop.run(flop)
  end

  defp filter_config(%{source: {_, Device}}),
    do: %{
      filter_builder: &DevicesFiltering.build_filters/2,
      sorter: &DevicesFiltering.sort_devices/2
    }

  defp filter_config(%{source: {_, DeploymentGroup}}),
    do: %{
      filter_builder: &DeploymentsFiltering.build_filters/2,
      sorter: &DeploymentsFiltering.sort_deployment_groups/2
    }

  defp filter_config(%{source: {_, Script}}),
    do: %{
      filter_builder: &ScriptsFiltering.build_filters/2,
      sorter: &ScriptsFiltering.sort_scripts/2
    }
end
