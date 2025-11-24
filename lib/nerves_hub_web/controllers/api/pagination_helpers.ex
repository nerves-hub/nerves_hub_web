defmodule NervesHubWeb.API.PaginationHelpers do
  @moduledoc """
  Shared helper functions for handling pagination in API controllers.
  """

  @doc """
  Converts pagination parameters from string keys and values (as they come from URL params)
  to atom keys with integer values (as expected by Flop and internal APIs).

  ## Examples

      iex> atomize_pagination_params(%{"page" => "1", "page_size" => "25"})
      %{page: 1, page_size: 25}

      iex> atomize_pagination_params(%{"page" => 2, "page_size" => 10})
      %{page: 2, page_size: 10}

      iex> atomize_pagination_params(%{})
      %{}

      iex> atomize_pagination_params(nil)
      %{}
  """
  @spec atomize_pagination_params(map() | nil) :: map()
  def atomize_pagination_params(pagination) when is_map(pagination) do
    pagination
    |> Enum.reduce(%{}, fn
      {"page", value}, acc when is_binary(value) ->
        Map.put(acc, :page, String.to_integer(value))

      {"page", value}, acc when is_integer(value) ->
        Map.put(acc, :page, value)

      {"page_size", value}, acc when is_binary(value) ->
        Map.put(acc, :page_size, String.to_integer(value))

      {"page_size", value}, acc when is_integer(value) ->
        Map.put(acc, :page_size, value)

      _other, acc ->
        acc
    end)
  end

  def atomize_pagination_params(_), do: %{}

  @doc """
  Converts Flop.Meta struct fields to the standard pagination response format
  used by the API.

  Maps:
  - current_page -> page_number
  - total_count -> total_entries
  - page_size -> page_size (unchanged)
  - total_pages -> total_pages (unchanged)

  ## Examples

      iex> meta = %Flop.Meta{current_page: 2, page_size: 10, total_count: 45, total_pages: 5}
      iex> format_pagination_meta(meta)
      %{page_number: 2, page_size: 10, total_entries: 45, total_pages: 5}
  """
  @spec format_pagination_meta(Flop.Meta.t()) :: map()
  def format_pagination_meta(%Flop.Meta{} = meta) do
    %{
      page_number: meta.current_page,
      page_size: meta.page_size,
      total_entries: meta.total_count,
      total_pages: meta.total_pages
    }
  end
end
