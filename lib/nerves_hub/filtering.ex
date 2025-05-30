defmodule NervesHub.Filtering do
  @moduledoc """
  Common filtering functionality for NervesHub resources.
  """
  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Products.Product
  alias NervesHub.Scripts.Script

  import Ecto.Query

  @doc """
  Common filter function that can be used across different resources.

  ## Parameters
    - base_query: The initial Ecto query to build upon
    - product: The product to filter by
    - filter_builder: Function that takes (query, filters) and returns modified query
    - sorter: Function that takes (query, sort) and returns modified query
    - opts: Map of options maybe including:
      - sort: Tuple of {direction, field} for sorting
      - filters: Map of filters to apply
      - pagination: Map of pagination options

  ## Returns
    A tuple containing:
    - List of entries matching the query
    - Flop metadata containing pagination information
  """
  @spec filter(Ecto.Query.t(), Product.t(), function(), function(), map()) ::
          {[%Device{}] | [%DeploymentGroup{}] | [%Script{}], Flop.Meta.t()}
  def filter(base_query, product, filter_builder, sorter, opts \\ %{}) do
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
end
