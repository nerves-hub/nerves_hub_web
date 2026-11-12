defmodule NervesHubWeb.Components.Pager do
  use NervesHubWeb, :component

  attr(:page_number, :any, default: 1)
  attr(:total_pages, :any, default: 1)
  attr(:rest, :global, include: ~w(phx-target))

  def render(assigns) do
    distance = 8
    start_range = round(max(1, assigns.page_number - distance / 2))
    end_range = min(round(start_range + distance), assigns.total_pages)

    assigns =
      Map.merge(assigns, %{start_range: start_range, end_range: end_range, distance: distance})

    ~H"""
    <div :if={@total_pages > 1} class="flex gap-4">
      <button class={["pager-button", @page_number < 2 && "invisible"]} phx-click="paginate" phx-value-page={@page_number - 1} {@rest}>
        <span class="lucide-chevron-left size-4 text-content-muted" aria-hidden="true"></span>
      </button>
      <button :for={page <- @start_range..@end_range} phx-click="paginate" phx-value-page={page} {@rest} class={"pager-button #{if page == @page_number do
      "active-page"
    end}"}>
        {page}
      </button>
      <button :if={@total_pages > @distance} class="pager-button" phx-click="paginate" phx-value-page="…" {@rest}>…</button>
      <button :if={@end_range != @total_pages} class="pager-button" phx-click="paginate" phx-value-page={@total_pages} {@rest}>{@total_pages}</button>
      <button class={["pager-button", @page_number == @total_pages && "invisible"]} phx-click="paginate" phx-value-page={@page_number + 1} {@rest}>
        <span class="lucide-chevron-right size-4 text-content-muted" aria-hidden="true"></span>
      </button>
    </div>
    """
  end

  attr(:pager, :any, required: true)
  attr(:page_sizes, :any, default: [25, 50, 100])
  attr(:rest, :global, include: ~w(phx-target))

  def render_with_page_sizes(assigns) do
    ~H"""
    <div
      data-extra-spacing={"#{not is_nil(Application.get_env(:nerves_hub, :featurebase_app_id))}"}
      class="sticky bottom-0 z-10 flex h-16 w-full shrink-0 flex-row border-0 border-t border-t-line-default bg-surface px-6 py-4 data-[extra-spacing=true]:pr-20"
    >
      <%= for {size, index} <- Enum.with_index(@page_sizes) do %>
        <button
          :if={(index == 0 && @pager.total_count > size) || @pager.total_count > Enum.at(@page_sizes, index - 1)}
          phx-click="set-paginate-opts"
          phx-value-page-size={size}
          {@rest}
          class={"pager-button cursor-pointer #{if size == @pager.page_size, do: "active-page"}"}
        >
          {size}
        </button>
      <% end %>
      <div class="ml-auto">
        <.render total_pages={@pager.total_pages} page_number={@pager.current_page} {@rest} />
      </div>
    </div>
    """
  end

  @doc """
  The pager as the design draws it, for the footer of a card: a page size
  select, then the pages as one segmented control, right aligned.

  Sends the same events as `render_with_page_sizes/1`: `set-paginate-opts`
  with `page-size`, and `paginate` with `page`.
  """
  attr(:id, :string, required: true, doc: "prefixes the page size form's ID, which LiveView needs")
  attr(:pager, :map, required: true, doc: "with `current_page`, `total_pages`, `page_size` and `total_count`")
  attr(:page_sizes, :list, default: [25, 50, 100])
  attr(:rest, :global, include: ~w(phx-target))

  def footer(assigns) do
    %{current_page: current, total_pages: total} = assigns.pager

    assigns =
      assign(assigns,
        pages: page_window(current, total),
        sizes?: assigns.pager.total_count > hd(assigns.page_sizes)
      )

    ~H"""
    <%!-- On a phone: thumb-sized previous and next buttons at either end, and
          which page this is between them, with the page size. --%>
    <div
      :if={@sizes? or @pager.total_pages > 1}
      class="flex h-12 shrink-0 items-center justify-end gap-2 border-t border-line-subtle pr-3 pl-4 max-sm:h-auto max-sm:py-3 max-sm:pr-4"
    >
      <span :if={@pager.total_pages > 1} class={["text-base/5 text-content-muted max-sm:order-2 max-sm:ml-auto sm:hidden", !@sizes? && "max-sm:mr-auto"]}>
        Page <span class="font-medium text-content-strong">{@pager.current_page}</span> of {@pager.total_pages}
      </span>
      <form :if={@sizes?} id={"#{@id}-page-size"} phx-change="set-paginate-opts" {@rest} class="grid grid-cols-1 max-sm:order-3 max-sm:mr-auto">
        <select
          name="page-size"
          aria-label="Rows per page"
          class="col-start-1 row-start-1 h-7.5 cursor-pointer appearance-none rounded border border-line-control border-b-line-strong bg-surface-raised bg-none py-0 pr-7 pl-2.5 text-ui text-content-body focus:outline focus:-outline-offset-1 focus:outline-focus-ring max-sm:h-11 max-sm:text-base"
        >
          <option :for={size <- @page_sizes} value={size} selected={size == @pager.page_size}>{size} per page</option>
        </select>
        <span class="pointer-events-none col-start-1 row-start-1 mr-2 lucide-chevron-down size-3.5 self-center justify-self-end text-content-muted" aria-hidden="true"></span>
      </form>

      <nav :if={@pager.total_pages > 1} aria-label="Pages" class="flex h-7 overflow-clip rounded border border-line-control bg-surface-raised shadow-xs max-sm:contents">
        <button
          type="button"
          aria-label="Previous page"
          disabled={@pager.current_page < 2}
          phx-click="paginate"
          phx-value-page={@pager.current_page - 1}
          class={[
            "flex items-center px-1.75 text-content-muted enabled:cursor-pointer enabled:hover:bg-surface-muted enabled:hover:text-content-strong disabled:text-content-faint",
            "max-sm:order-1 max-sm:size-11 max-sm:shrink-0 max-sm:justify-center max-sm:rounded-md max-sm:border max-sm:border-line-control max-sm:bg-surface-raised max-sm:shadow-xs"
          ]}
          {@rest}
        >
          <span class="lucide-chevron-left size-3.5 max-sm:size-4.5" aria-hidden="true"></span>
        </button>
        <%= for page <- @pages do %>
          <span :if={page == :gap} class="flex w-7 shrink-0 items-center justify-center border-l border-line-control text-xs text-content-faint max-sm:hidden">…</span>
          <button
            :if={page != :gap}
            type="button"
            aria-current={if page == @pager.current_page, do: "page"}
            phx-click="paginate"
            phx-value-page={page}
            class="flex min-w-7 shrink-0 cursor-pointer items-center justify-center border-l border-line-control px-1.5 text-xs font-medium text-content-muted hover:bg-surface-muted hover:text-content-strong aria-[current=page]:bg-surface-muted aria-[current=page]:text-content-strong max-sm:hidden"
            {@rest}
          >
            {page}
          </button>
        <% end %>
        <button
          type="button"
          aria-label="Next page"
          disabled={@pager.current_page >= @pager.total_pages}
          phx-click="paginate"
          phx-value-page={@pager.current_page + 1}
          class={[
            "flex items-center border-l border-line-control px-1.75 text-content-muted enabled:cursor-pointer enabled:hover:bg-surface-muted enabled:hover:text-content-strong disabled:text-content-faint",
            "max-sm:order-4 max-sm:size-11 max-sm:shrink-0 max-sm:justify-center max-sm:rounded-md max-sm:border max-sm:border-line-control max-sm:bg-surface-raised max-sm:shadow-xs"
          ]}
          {@rest}
        >
          <span class="lucide-chevron-right size-3.5 max-sm:size-4.5" aria-hidden="true"></span>
        </button>
      </nav>
    </div>
    """
  end

  # Up to five pages around the current one, plus the first and last with a
  # gap where pages are skipped.
  defp page_window(_current, total) when total <= 7, do: Enum.to_list(1..max(total, 1))

  defp page_window(current, total) do
    first = current |> Kernel.-(2) |> max(2) |> min(total - 5)
    middle = Enum.to_list(first..(first + 4))

    [1] ++
      if(first > 2, do: [:gap], else: []) ++
      middle ++
      if(first + 4 < total - 1, do: [:gap], else: []) ++
      [total]
  end
end
