defmodule NervesHubWeb.Components.DeviceColumns do
  @moduledoc """
  The devices list's Columns panel: which of the table's columns show.

  A slide-over built like the Filters panel (`NervesHubWeb.Components.DeviceFilters`).
  The choice is saved to the user's display preferences as it changes
  (`device_list_columns`), so it's the same on every product's devices list.
  The Device column is always shown.
  """

  use NervesHubWeb, :component

  alias Phoenix.LiveView.JS

  # In the table's order, each with what its cells show.
  @columns [
    {:health, "Health", "Healthy, warning or unhealthy, from its last report"},
    {:firmware, "Firmware", "The version it runs, and an update's progress"},
    {:platform, "Platform", "The platform its firmware was built for"},
    {:deployment_group, "Deployment group", "The group it takes releases from"},
    {:connected_info, "Connection", "Online now, or when it was last seen"},
    {:tags, "Tags", "Every tag the device has"}
  ]

  @doc "The columns the panel can hide, in the table's order."
  @spec columns() :: [atom()]
  def columns(), do: Enum.map(@columns, &elem(&1, 0))

  @doc "Shows the panel. It's rendered by the server, so this only pushes the event."
  def open(), do: JS.push("open-columns")

  defp close() do
    "close-columns"
    |> JS.push()
    |> JS.hide(
      to: "#columns-panel",
      transition: {"transition-transform duration-150 ease-in", "translate-x-0", "translate-x-full"},
      time: 150
    )
  end

  attr(:selected, :list, default: nil, doc: "the columns shown, or nil for all of them")

  @doc "The Columns slide-over."
  def panel(assigns) do
    selected = Enum.map(assigns.selected || columns(), &to_string/1)

    assigns =
      assigns
      |> assign(:columns, @columns)
      |> assign(:selected, selected)
      |> assign(:shown, 1 + Enum.count(columns(), &(to_string(&1) in selected)))
      |> assign(:total, 1 + length(@columns))

    ~H"""
    <aside
      id="columns-panel"
      role="dialog"
      aria-labelledby="columns-panel-title"
      class="fixed top-(--topbar-height) right-0 bottom-0 z-50 flex w-95 max-w-full flex-col border-l border-line-default bg-surface-raised shadow-[-12px_0_32px_rgb(24_24_27/0.08),-1px_0_2px_rgb(24_24_27/0.04)]"
      phx-mounted={JS.transition({"transition-transform duration-150 ease-out", "translate-x-full", "translate-x-0"}, time: 150)}
      phx-window-keydown={close()}
      phx-key="escape"
    >
      <header class="flex h-13 shrink-0 items-center justify-between border-b border-line-subtle pr-3 pl-5">
        <div class="flex items-baseline gap-2">
          <h2 id="columns-panel-title" class="text-list-title text-content-strong">Columns</h2>
          <span id="columns-shown" class="text-xs text-content-muted">{@shown} of {@total} shown</span>
        </div>
        <div class="flex items-center gap-1.5">
          <kbd class="inline-flex items-center rounded-[3px] border border-line-default px-1.25 py-px font-sans text-[11px]/3.5 font-normal text-content-faint">
            esc
          </kbd>
          <button
            type="button"
            aria-label="Close columns"
            title="Close"
            phx-click={close()}
            class="flex size-7 shrink-0 cursor-pointer items-center justify-center rounded text-content-muted hover:bg-surface-muted hover:text-content-strong focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus-ring"
          >
            <span class="lucide-x size-3.75" aria-hidden="true"></span>
          </button>
        </div>
      </header>

      <div class="min-h-0 flex-1 overflow-y-auto px-5 pt-1 pb-4">
        <p class="border-b border-line-subtle pt-2.5 pb-3.5 text-xs text-content-muted">
          Saved to your account, so every product's devices list shows the same columns.
        </p>

        <form id="columns-form" phx-change="update-columns" class="flex flex-col gap-1.5 pt-3.5">
          <span class="text-label text-content-muted uppercase">Shown in the list</span>
          <input type="hidden" name="columns[]" value="" />
          <div class="flex flex-col">
            <div class="flex items-start gap-2.5 py-2.25">
              <span class="flex h-4 shrink-0 items-center">
                <span class="flex size-3.5 items-center justify-center rounded-[3px] bg-line-control" aria-hidden="true">
                  <span class="lucide-check--bold size-2.5 text-white"></span>
                </span>
              </span>
              <span class="flex min-w-0 flex-1 flex-col gap-0.5">
                <span class="text-ui/4 font-medium text-content-strong">Device</span>
                <span class="text-xs text-content-muted">Its identifier, which opens the device</span>
              </span>
              <span class="shrink-0 text-xs text-content-faint">Always shown</span>
            </div>
            <label
              :for={{column, label, description} <- @columns}
              id={"column-#{column}"}
              for={"column-#{column}-input"}
              class="group/column flex cursor-pointer items-start gap-2.5 border-t border-line-subtle py-2.25"
            >
              <span class="flex h-4 shrink-0 items-center">
                <input
                  id={"column-#{column}-input"}
                  type="checkbox"
                  name="columns[]"
                  value={column}
                  checked={to_string(column) in @selected}
                  class="size-3.5 shrink-0 rounded-[3px] border-line-control bg-surface-raised checked:bg-primary focus:ring-0 focus:ring-offset-0 focus-visible:ring-2 focus-visible:ring-focus-ring"
                />
              </span>
              <span class="flex min-w-0 flex-1 flex-col gap-0.5">
                <span class="text-ui/4 font-medium text-content-body group-has-checked/column:text-content-strong">{label}</span>
                <span class="text-xs text-content-muted">{description}</span>
              </span>
            </label>
          </div>
        </form>
      </div>

      <footer class="flex h-15 shrink-0 items-center justify-between border-t border-line-subtle bg-surface px-5">
        <button type="button" phx-click="show-all-columns" class="cursor-pointer text-ui/4 font-medium text-content-body hover:text-content-strong">
          Show all
        </button>
        <.button type="button" style="primary" phx-click={close()}>Done</.button>
      </footer>
    </aside>
    """
  end
end
