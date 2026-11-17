defmodule NervesHubWeb.Components.ProductList do
  @moduledoc """
  Pieces the firmware and archive lists share: the footer with its pager, the
  sort arrow on a column header, and how a UUID, a size and an upload time are
  written in a row.
  """
  use NervesHubWeb, :component

  attr(:id, :string, required: true, doc: "prefixes the ids of the footer and its page size select")
  attr(:pager, :map, required: true)
  attr(:label, :string, required: true, doc: "what the list holds, for the page size select's label")
  slot(:hint, doc: "said after the count on wide screens, such as how to upload")

  @doc """
  The count of what's shown, a page size select and previous and next buttons.

  Sends `set-paginate-opts` and `paginate`, like the shared pager does.
  """
  def list_footer(assigns) do
    %{current_page: page, page_size: size, total_count: total} = assigns.pager

    assigns =
      assign(assigns,
        first: (page - 1) * size + 1,
        last: min(page * size, total),
        last_page: max(assigns.pager.total_pages, 1)
      )

    ~H"""
    <div id={"#{@id}-pager"} class="flex items-center justify-between gap-4 px-4 pb-6 @3xl:px-6">
      <p class="min-w-0 truncate font-mono text-xs text-content-body">
        {@first}–{@last} of {@pager.total_count}<span :if={@hint != []} class="max-sm:hidden"><span class="text-content-faint"> · </span><span class="font-sans text-ui text-content-muted">{render_slot(
          @hint
        )}</span></span>
      </p>

      <div class="flex shrink-0 items-center gap-4">
        <form id={"#{@id}-page-size"} phx-change="set-paginate-opts" class="flex items-center gap-1.5">
          <label for={"#{@id}-page-size-select"} class="text-ui text-content-body max-sm:hidden">Per page</label>
          <span class="grid grid-cols-1">
            <select
              id={"#{@id}-page-size-select"}
              name="page-size"
              aria-label={"#{@label} per page"}
              class="col-start-1 row-start-1 h-7 cursor-pointer appearance-none rounded-sm border border-line-control bg-surface-raised bg-none py-0 pr-6 pl-2 font-mono text-xs text-content-strong focus:outline focus:-outline-offset-1 focus:outline-focus-ring"
            >
              <option :for={option <- [25, 50, 100]} value={option} selected={option == @pager.page_size}>{option}</option>
            </select>
            <span class="pointer-events-none col-start-1 row-start-1 mr-1.5 lucide-chevron-down size-3 self-center justify-self-end text-content-muted" aria-hidden="true"></span>
          </span>
        </form>

        <nav aria-label="Pages" class="flex items-center">
          <button
            type="button"
            aria-label="Previous page"
            disabled={@pager.current_page < 2}
            phx-click="paginate"
            phx-value-page={@pager.current_page - 1}
            class="flex size-7 shrink-0 items-center justify-center rounded-l-sm border border-line-control bg-surface-raised text-content-body enabled:cursor-pointer enabled:hover:bg-surface-muted disabled:border-line-default disabled:text-content-faint"
          >
            <span class="lucide-chevron-left size-3.5" aria-hidden="true"></span>
          </button>
          <span aria-current="page" class="flex h-7 items-center border-y border-line-default bg-surface-raised px-2.5 font-mono text-xs whitespace-nowrap text-content-strong">
            {@pager.current_page} / {@last_page}
          </span>
          <button
            type="button"
            aria-label="Next page"
            disabled={@pager.current_page >= @last_page}
            phx-click="paginate"
            phx-value-page={@pager.current_page + 1}
            class="flex size-7 shrink-0 items-center justify-center rounded-r-sm border border-line-control bg-surface-raised text-content-body enabled:cursor-pointer enabled:hover:bg-surface-muted disabled:border-line-default disabled:text-content-faint"
          >
            <span class="lucide-chevron-right size-3.5" aria-hidden="true"></span>
          </button>
        </nav>
      </div>
    </div>
    """
  end

  attr(:field, :string, required: true)
  attr(:current, :string, required: true)
  attr(:direction, :string, required: true)

  @doc "The arrow on the column the list is sorted by."
  def sort_arrow(assigns) do
    ~H"""
    <span
      :if={@field == @current}
      class={["size-3 text-content-body", (@direction == "asc" && "lucide-arrow-up") || "lucide-arrow-down"]}
      aria-label={(@direction == "asc" && "ascending") || "descending"}
    ></span>
    """
  end

  @doc "The start and end of a UUID, which is enough to tell builds apart."
  @spec short_uuid(String.t()) :: String.t()
  def short_uuid(uuid) when byte_size(uuid) > 12 do
    String.slice(uuid, 0, 8) <> "…" <> String.slice(uuid, -4, 4)
  end

  def short_uuid(uuid), do: uuid

  @doc "A file size in kilobytes or megabytes, to one decimal place."
  @spec format_megabytes(non_neg_integer() | nil) :: String.t()
  def format_megabytes(nil), do: "—"

  def format_megabytes(size) when size < 100_000 do
    "#{Float.round(size / 1_000, 1)} KB"
  end

  def format_megabytes(size), do: "#{Float.round(size / 1_000_000, 1)} MB"

  @doc "Within the last day, how long ago; before that, the day."
  @spec uploaded_label(NaiveDateTime.t(), String.t()) :: String.t()
  def uploaded_label(at, time_zone) do
    if NaiveDateTime.diff(NaiveDateTime.utc_now(), at, :hour) < 24 do
      from_now(at)
    else
      day_label(at, time_zone)
    end
  end
end
