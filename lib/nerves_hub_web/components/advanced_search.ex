defmodule NervesHubWeb.Components.AdvancedSearch do
  @moduledoc """
  Advanced search field for the device list page.

  The search bar itself is a contenteditable rich text box (`phx-hook="AdvancedQueryEditor"`)
  that tokenizes and autosuggests against the whitelist defined in
  `NervesHub.Devices.AdvancedQuery.Schema`. It fills the width it's given;
  on focus it reveals suggestions below, similar to a command palette, and
  hides them again on blur. Validation is always re-checked
  server-side by `NervesHub.Devices.AdvancedQuery.interpret/2` on apply - the
  client-side tokenizer is for highlighting/suggestions only.

  Plain text that isn't a query expression (e.g. a pasted device identifier)
  is applied as a free-text search: the server rewrites it to
  `search like "%text%"` and the editor re-syncs to show that form.
  """

  use NervesHubWeb, :component

  attr(:query, :string, required: true)
  attr(:error, :string, default: nil)
  attr(:schema_json, :string, required: true)

  def field(assigns) do
    ~H"""
    <div id="advanced-query-editor-wrapper" phx-hook="AdvancedQueryEditor" data-schema={@schema_json} data-value={@query} class="relative min-w-0 flex-1">
      <div
        data-role="box"
        class="rounded border border-line-control bg-surface-raised shadow-xs focus-within:border-line-strong focus-within:ring-2 focus-within:ring-focus-ring/40"
      >
        <div class="grid h-7.5 grid-cols-1 max-sm:h-10">
          <span class="pointer-events-none col-start-1 row-start-1 ml-2.5 lucide-search size-3.75 self-center text-content-muted" aria-hidden="true" />

          <div
            id="advanced-query-input"
            data-role="editor"
            phx-update="ignore"
            contenteditable="true"
            spellcheck="false"
            autocorrect="off"
            autocapitalize="off"
            aria-label="Search devices"
            class={
              [
                "col-start-1 row-start-1 mr-9 ml-8 scrollbar-none block h-7.5 truncate overflow-x-scroll py-1.75 font-mono text-xs/4 text-content-body outline-none",
                # 16px on a phone, or iOS zooms the page when the field takes focus.
                "max-sm:h-10 max-sm:py-2.5 max-sm:text-base/5",
                "mask-[linear-gradient(to_right,transparent,black_2%,black_98%,transparent)]"
              ]
            }
          ></div>

          <%!-- The placeholder, toggled by the hook. --%>
          <div
            id="advanced-query-placeholder"
            data-role="placeholder"
            phx-update="ignore"
            class={[
              "pointer-events-none col-start-1 row-start-1 ml-8 flex items-center gap-1.5 truncate text-ui/4 text-content-faint max-sm:text-sm",
              @query != "" && "hidden"
            ]}
          >
            <span class="sm:hidden">Identifier, tag or filter</span>
            <span class="max-sm:hidden">Search devices, or filter like</span>
            <code class="font-mono text-xs text-content-muted max-sm:hidden">platform = "rpi4"</code>
          </div>

          <%!-- Pressing "/" focuses the field. Hidden by the hook once there's a query, when the clear button takes its place. --%>
          <kbd
            id="search-icon"
            phx-update="ignore"
            data-role="search-icon"
            class="pointer-events-none col-start-1 row-start-1 mr-1.5 inline-flex h-4.5 items-center self-center justify-self-end rounded-[3px] border border-line-default px-1.25 text-[11px]/3.5 text-content-muted max-sm:invisible"
          >
            /
          </kbd>

          <button
            type="button"
            data-role="clear"
            class="col-start-1 row-start-1 mr-2 hidden self-center justify-self-end text-content-muted hover:cursor-pointer hover:text-content-strong"
            title="Clear"
            aria-label="Clear advanced query"
            phx-update="ignore"
            id="clear-button"
          >
            <span class="lucide-x size-4" />
          </button>
        </div>
      </div>

      <div data-role="hints" class="absolute inset-x-0 top-full z-40 hidden">
        <div data-role="suggestions" class="relative"></div>
        <p :if={@error} class="mt-1 rounded border border-line-default bg-surface-overlay px-3 py-1.5 text-xs text-alert-content shadow-overlay">{@error}</p>
      </div>
    </div>
    """
  end
end
