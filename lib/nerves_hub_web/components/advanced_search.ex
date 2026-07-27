defmodule NervesHubWeb.Components.AdvancedSearch do
  @moduledoc """
  Advanced search field for the device list page.

  The search bar itself is a contenteditable rich text box (`phx-hook="AdvancedQueryEditor"`)
  that tokenizes and autosuggests against the whitelist defined in
  `NervesHub.Devices.AdvancedQuery.Schema`. On focus it expands and reveals
  hints/suggestions below, similar to a command palette. Collapses back to a
  normal-looking search box on blur. Validation is always re-checked
  server-side by `NervesHub.Devices.AdvancedQuery.parse/2` on apply - the
  client-side tokenizer is for highlighting/suggestions only.
  """

  use NervesHubWeb, :component

  attr(:query, :string, required: true)
  attr(:error, :string, default: nil)
  attr(:schema_json, :string, required: true)

  def field(assigns) do
    ~H"""
    <div
      id="advanced-query-editor-wrapper"
      phx-hook="AdvancedQueryEditor"
      data-schema={@schema_json}
      data-value={@query}
      class="h-8 w-64 transition-[width] duration-400 ease-in-out [&[data-value]:not([data-value=''])]:w-136"
    >
      <div data-role="box" class="bg-surface-muted border-base-600 rounded border">
        <div class="grid grid-cols-1">
          <div
            id="advanced-query-input"
            data-role="editor"
            phx-update="ignore"
            contenteditable="true"
            spellcheck="false"
            autocorrect="off"
            autocapitalize="off"
            class={[
              "ff-m scrollbar-none text-base-400 col-start-1 row-start-1 mr-9 block h-8 truncate overflow-x-scroll py-1.5 pl-3 text-sm font-normal outline-none",
              "mask-[linear-gradient(to_right,transparent,black_2%,black_98%,transparent)]"
            ]}
          ></div>

          <%!-- Placeholder hints that pressing "/" focuses the field. Toggled by the hook. --%>
          <div
            id="advanced-query-placeholder"
            data-role="placeholder"
            phx-update="ignore"
            class={[
              "ff-m text-base-500 pointer-events-none col-start-1 row-start-1 flex h-8 items-center gap-1.5 pl-3 text-sm",
              @query != "" && "hidden"
            ]}
          >
            <kbd class="bg-base-800 border-base-600 text-base-300 inline-flex size-4 items-center justify-center rounded border text-xs leading-none">/</kbd>
            <span>Advanced search</span>
          </div>

          <span
            id="search-icon"
            phx-update="ignore"
            data-role="search-icon"
            class="lucide-search--light text-content-faint pointer-events-none col-start-1 row-start-1 mr-3 size-5 self-center justify-self-end"
          />

          <button
            type="button"
            data-role="clear"
            class="hover:text-base-200 text-base-400 col-start-1 row-start-1 mr-3 hidden self-center justify-self-end hover:cursor-pointer"
            title="Clear"
            aria-label="Clear advanced query"
            phx-update="ignore"
            id="clear-button"
          >
            <div class="bg-surface-muted"><span class="lucide-x--light text-content-faint size-4" /></div>
          </button>
        </div>
      </div>

      <div data-role="hints" class="hidden">
        <div data-role="suggestions" class="relative"></div>
        <p :if={@error} class="text-xs text-red-400">{@error}</p>
      </div>
    </div>
    """
  end
end
