defmodule NervesHubWeb.Components.Pagination do
  use NervesHubWeb, :component

  @doc """
  Creates a series of pagination links to use with a Phoenix.LiveView page.

  When one of the links is clicked, it sends a `"paginate"` event with the
  expected page number for the LiveView to handle.

  Requires a map with `:total_pages` key or `:total_records` and `:page_size`
  keys to calculate `:total_pages` for you.

  Likewise, you can supply your list of records and applicable options (such
  as `:page_size`) to `pagination_links/2` which will calculate `:total_pages`
  for you.
  """
  def links(%{total_pages: _, links: true} = assigns) do
    raw_links = Scrivener.HTML.raw_pagination_links(assigns, distance: Map.get(assigns, :distance, 8))

    assigns =
      assigns
      |> Map.put_new(:page_number, 1)
      |> Map.put_new(:raw_links, raw_links)

    ~H"""
    <div class="btn-group btn-group-toggle">
      <%= for {text, page} <- @raw_links do %>
        <%= if text == :ellipsis do %>
          <span class="btn btn-secondary btn-sm">
            <%= page %>
          </span>
        <% else %>
          <.link class={"btn btn-secondary btn-sm #{if page == assigns.page_number, do: "active"}"}
                patch={"?page=#{page}"}>
            <%= if text == :ellipsis, do: page, else: text %>
          </.link>
        <% end %>
      <% end %>
    </div>
    """
  end

  def links(%{total_pages: _} = assigns) do
    raw_links = Scrivener.HTML.raw_pagination_links(assigns, distance: Map.get(assigns, :distance, 8))

    assigns =
      assigns
      |> Map.put_new(:page_number, 1)
      |> Map.put_new(:raw_links, raw_links)

    ~H"""
    <div class="btn-group btn-group-toggle">
      <div :for={{text, page} <- @raw_links}>
        <.link patch={"?page=#{page}"} class={"btn btn-secondary btn-sm #{if page == @page_number, do: "active"}"}>
          <%= if text == :ellipsis, do: page, else: text %>
        </.link>
      </div>
    </div>
    """
  end

  def links(%{total_records: record_count, page_size: size} = assigns) do
    assigns
    |> Map.put(:total_pages, ceil(record_count / size))
    |> links()
  end
end
