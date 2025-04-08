defmodule NervesHubWeb.Components.Pager do
  use NervesHubWeb, :component

  attr(:page_number, :any, default: 1)
  attr(:total_pages, :any, default: 1)

  def render(assigns) do
    distance = 8
    start_range = round(max(1, assigns.page_number - distance / 2))
    end_range = min(round(start_range + distance), assigns.total_pages)

    assigns =
      Map.merge(assigns, %{start_range: start_range, end_range: end_range, distance: distance})

    ~H"""
    <div :if={@total_pages > 1} class="flex gap-4">
      <button class={["pager-button", @page_number < 2 && "invisible"]} phx-click="paginate" phx-value-page={@page_number - 1}>
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20" fill="none">
          <path d="M11.6667 5.83337L7.5 10L11.6667 14.1667" stroke="#A1A1AA" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round" />
        </svg>
      </button>
      <button :for={page <- @start_range..@end_range} phx-click="paginate" phx-value-page={page} class={"pager-button #{if page == @page_number do "active-page" end}"}>
        {page}
      </button>
      <button :if={@total_pages > @distance} class="pager-button" phx-click="paginate" phx-value-page="…">…</button>
      <button :if={@end_range != @total_pages} class="pager-button" phx-click="paginate" phx-value-page={@total_pages}>{@total_pages}</button>
      <button class={["pager-button", @page_number == @total_pages && "invisible"]} phx-click="paginate" phx-value-page={@page_number + 1}>
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20" fill="none">
          <path d="M8.3335 5.83337L12.5002 10L8.3335 14.1667" stroke="#A1A1AA" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round" />
        </svg>
      </button>
    </div>
    """
  end

  attr(:pager, :any, required: true)
  attr(:page_sizes, :any, default: [25, 50, 100])

  def render_with_page_sizes(assigns) do
    ~H"""
    <div class="sticky bottom-0 h-16 w-full shrink-0 flex flex-row border-0 bg-base-950 border-t border-t-base-700 px-6 py-4 z-10">
      <%= for {size, index} <- Enum.with_index(@page_sizes) do %>
        <button
          :if={(index == 0 && @pager.total_count > size) || @pager.total_count > Enum.at(@page_sizes, index - 1)}
          phx-click="set-paginate-opts"
          phx-value-page-size={size}
          class={"pager-button #{if size == @pager.page_size, do: "active-page"}"}
        >
          {size}
        </button>
      <% end %>
      <div class="ml-auto">
        <.render total_pages={@pager.total_pages} page_number={@pager.current_page} />
      </div>
    </div>
    """
  end
end
