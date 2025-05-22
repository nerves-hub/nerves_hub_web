defmodule NervesHub.Filtering do
  @moduledoc """
  Common filtering functionality for NervesHub resources.
  """

  import Ecto.Query

  @doc """
  Common filter function that can be used across different resources.

  ## Parameters
    - base_query: The initial Ecto query to build upon
    - product: The product to filter by
    - opts: Map of options including:
      - sort: Tuple of {direction, field} for sorting
      - filters: Map of filters to apply
      - page: Page number for pagination
      - page_size: Number of items per page
    - filter_builder: Function that takes (query, filters) and returns modified query
    - sorter: Function that takes (query, sort) and returns modified query
  """
  def filter(base_query, product, opts \\ %{}, filter_builder, sorter) do
    opts = Map.reject(opts, fn {_key, val} -> is_nil(val) end)

    sorting = Map.get(opts, :sort, {:asc, :name})
    filters = Map.get(opts, :filters, %{})

    flop = %Flop{
      page: Map.get(opts, :page, 1),
      page_size: Map.get(opts, :page_size, 25)
    }

    base_query
    |> where([q], q.product_id == ^product.id)
    |> filter_builder.(filters)
    |> sorter.(sorting)
    |> Flop.run(flop)
  end
end
