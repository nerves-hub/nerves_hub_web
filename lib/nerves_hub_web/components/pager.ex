defmodule NervesHubWeb.Components.Pager do
  use NervesHubWeb, :component

  attr(:page_number, :any, default: 1)
  attr(:total_pages, :any)

  def render(assigns) do
    distance = 8
    start_range = round(max(1, assigns.page_number - distance / 2))
    end_range = min(round(start_range + distance), assigns.total_pages)

    assigns =
      Map.merge(assigns, %{start_range: start_range, end_range: end_range, distance: distance})

    ~H"""
    <div :if={@total_pages > 1} class="flex gap-4">
      <button class="pager-button" disabled={@page_number < 2} phx-click="paginate" phx-value-page={@page_number - 1}>
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20" fill="none">
          <path d="M11.6667 5.83337L7.5 10L11.6667 14.1667" stroke="#A1A1AA" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round" />
        </svg>
      </button>
      <button :for={page <- @start_range..@end_range} phx-click="paginate" phx-value-page={page} class={"pager-button #{if page == @page_number do "active-page" end}"}>
        <%= page %>
      </button>
      <button :if={@total_pages > @distance} class="pager-button" phx-click="paginate" phx-value-page="…">…</button>
      <button :if={@end_range != @total_pages} class="pager-button" phx-click="paginate" phx-value-page={@total_pages}><%= @total_pages %></button>
      <button class={["pager-button", @page_number == @total_pages && "invisible"]} phx-click="paginate" phx-value-page={@page_number + 1}>
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20" fill="none">
          <path d="M8.3335 5.83337L12.5002 10L8.3335 14.1667" stroke="#A1A1AA" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round" />
        </svg>
      </button>
    </div>
    """
  end
end
