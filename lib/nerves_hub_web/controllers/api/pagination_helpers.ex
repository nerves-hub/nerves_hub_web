defmodule NervesHubWeb.API.PaginationHelpers do
  @moduledoc """
  Shared helper functions for handling pagination in API controllers.
  """

  # One request loads at most this many records, whatever page size it asks
  # for. A device in a list comes with its associations preloaded, so an
  # unbounded page could load a whole fleet at once.
  @max_page_size 100

  # Flop turns the page into an OFFSET, which Postgres reads as a bigint. A
  # page that fits in 32 bits keeps it in range at any page size.
  @max_page 2_147_483_647

  @doc """
  The most records one page of an API list holds. A larger page size is
  lowered to it.
  """
  def max_page_size(), do: @max_page_size

  @doc """
  The highest page number an API list accepts.
  """
  def max_page(), do: @max_page

  @doc """
  Reads a list request's `pagination` param into the `page` and `page_size`
  Flop expects.

  Each must be a whole number of 1 or more, as an integer or as a string from
  the query, and the page no more than #{@max_page}. One that is missing or
  empty is left out, so the list's own default applies. A page size over
  #{@max_page_size} is lowered to #{@max_page_size}, and the response's
  pagination says which was used.

  Anything else is an unusable query parameter, which
  `NervesHubWeb.API.FallbackController` answers with a 422. Flop applies no
  limit at all to a page or page size under 1, so one getting through would
  list every record.

  ## Examples

      iex> cast_pagination_params(%{"page" => "2", "page_size" => "25"})
      {:ok, %{page: 2, page_size: 25}}

      iex> cast_pagination_params(%{"page" => 2, "page_size" => 10})
      {:ok, %{page: 2, page_size: 10}}

      iex> cast_pagination_params(%{"page_size" => "500"})
      {:ok, %{page_size: 100}}

      iex> cast_pagination_params(%{"page" => "", "unknown" => "value"})
      {:ok, %{}}

      iex> cast_pagination_params(nil)
      {:ok, %{}}

      iex> cast_pagination_params(%{"page_size" => "0"})
      {:error, {:invalid_query_param, ~s|pagination[page_size] must be a whole number of 1 or more, got "0".|}}

      iex> cast_pagination_params(%{"page" => "abc"})
      {:error, {:invalid_query_param, ~s|pagination[page] must be a whole number from 1 to 2147483647, got "abc".|}}
  """
  @spec cast_pagination_params(term()) ::
          {:ok, %{optional(:page) => pos_integer(), optional(:page_size) => pos_integer()}}
          | {:error, {:invalid_query_param, String.t()}}
  def cast_pagination_params(nil), do: {:ok, %{}}

  def cast_pagination_params(pagination) when is_map(pagination) do
    with {:ok, page} <- cast_page(pagination["page"]),
         {:ok, page_size} <- cast_page_size(pagination["page_size"]) do
      {:ok, Map.reject(%{page: page, page_size: page_size}, fn {_key, value} -> is_nil(value) end)}
    end
  end

  def cast_pagination_params(pagination) do
    invalid("pagination must be an object, such as pagination[page]=2&pagination[page_size]=50", pagination)
  end

  defp cast_page(raw) do
    case whole_number(raw) do
      {:ok, page} when page >= 1 and page <= @max_page -> {:ok, page}
      :missing -> {:ok, nil}
      _invalid -> invalid("pagination[page] must be a whole number from 1 to #{@max_page}", raw)
    end
  end

  defp cast_page_size(raw) do
    case whole_number(raw) do
      {:ok, page_size} when page_size >= 1 -> {:ok, min(page_size, @max_page_size)}
      :missing -> {:ok, nil}
      _invalid -> invalid("pagination[page_size] must be a whole number of 1 or more", raw)
    end
  end

  defp whole_number(nil), do: :missing
  defp whole_number(""), do: :missing
  defp whole_number(value) when is_integer(value), do: {:ok, value}

  defp whole_number(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> {:ok, number}
      _other -> :error
    end
  end

  defp whole_number(_value), do: :error

  defp invalid(message, raw), do: {:error, {:invalid_query_param, "#{message}, got #{inspect(raw)}."}}

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
