defmodule NervesHubWeb.Components.FilterSidebar do
  use NervesHubWeb, :component

  attr(:show, :boolean, required: true)
  attr(:current_filters, :map, required: true)
  attr(:filter_options, :map, required: true)
  attr(:on_toggle, :any, required: true)
  attr(:on_update, :any, required: true)
  attr(:on_reset, :any, required: true)

  def render(assigns) do
    ~H"""
    <div class="pointer-events-none fixed inset-y-0 right-0 flex max-w-full pl-10 sm:pl-16 z-40">
      <div class={[
        "pointer-events-auto w-screen max-w-80 mt-[55px] flex h-full flex-col border-t border-l border-zinc-700 bg-base-900 shadow-filter-slider transition-transform",
        !@show && "translate-x-full",
        !@show && "invisible"
      ]}>
        <div class="h-0 flex-1 overflow-y-auto">
          <div class="flex items-center h-14 px-4 py-3 border-b border-zinc-700">
            <h4 class="text-base font-semibold">Filters</h4>

            <button class="ml-auto p-1.5" type="button" phx-click={@on_toggle} phx-value-toggle={to_string(@show)}>
              <svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 20 20" fill="none">
                <path
                  d="M10.0002 9.99998L5.8335 5.83331M10.0002 9.99998L14.1668 14.1666M10.0002 9.99998L14.1668 5.83331M10.0002 9.99998L5.8335 14.1666"
                  stroke="#A1A1AA"
                  stroke-width="1.2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
              </svg>
            </button>
          </div>

          <div class="flex flex-1 flex-col pb-4">
            <form id="filter-form" class="px-4 grow" phx-change={@on_update}>
              <div :for={{field, options} <- @filter_options} class="mt-6">
                <label class="sidebar-label" for={"input_#{field}"}>{options.label}</label>
                <%= case options.type do %>
                  <% :text -> %>
                    <input class="sidebar-text-input" type="text" name={field} id={"input_#{field}"} value={@current_filters[field]} phx-debounce="500" />
                  <% :select -> %>
                    <select class="sidebar-select" name={field} id={"input_#{field}"}>
                      <option :for={{label, value} <- options.values} value={value} selected={@current_filters[field] == value}>
                        {label}
                      </option>
                    </select>
                  <% :number -> %>
                    <input class="sidebar-text-input" type="number" name={field} id={"input_#{field}"} value={@current_filters[field]} phx-debounce="100" />
                <% end %>
              </div>
            </form>
          </div>
        </div>

        <div class="flex shrink-0 justify-end h-16 px-4 py-4 mb-14 border-t border-zinc-700">
          <button class="sidebar-button" type="button" phx-click={@on_reset}>Reset Filters</button>
        </div>
      </div>
    </div>
    """
  end
end
