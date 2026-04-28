defmodule NervesHubWeb.Components.FilterSidebar do
  use NervesHubWeb, :component

  attr(:show, :boolean, required: true)
  attr(:current_filters, :map, required: true)
  attr(:on_toggle, :any, default: "toggle-filters")
  attr(:on_update, :any, default: "update-filters")
  attr(:on_reset, :any, default: "reset-filters")

  slot(:filter, required: true) do
    attr(:attr, :string, required: true, doc: "Filter attribute name")
    attr(:label, :string, required: true)
    attr(:type, :atom, required: true)
    attr(:values, :list)
  end

  def render(assigns) do
    # Convert filter attributes to atoms for getting current filter values
    assigns =
      update(assigns, :filter, fn filters ->
        Enum.map(filters, fn %{attr: attr} = filter ->
          %{filter | attr: String.to_existing_atom(attr)}
        end)
      end)

    ~H"""
    <div class="pointer-events-none fixed inset-y-0 right-0 z-40 flex max-w-full pl-10 sm:pl-16">
      <div class={[
        "bg-surface-muted border-base-700 shadow-filter-slider pointer-events-auto mt-[55px] flex h-full w-screen max-w-80 flex-col border-t border-l transition-transform",
        !@show && "translate-x-full",
        !@show && "invisible"
      ]}>
        <div class="h-0 flex-1 overflow-y-auto">
          <div class="border-base-700 flex h-14 items-center border-b px-4 py-3">
            <h4 class="text-base font-semibold">Filters</h4>

            <button class="ml-auto p-1.5" type="button" phx-click={@on_toggle} phx-value-toggle={to_string(@show)}>
              <svg xmlns="http://www.w3.org/2000/svg" class="size-5" viewBox="0 0 20 20" fill="none">
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
            <form id="filter-form" class="grow px-4" phx-change={@on_update}>
              <div :for={filter <- @filter} class="mt-6">
                <label class="sidebar-label" for={"input_#{filter.attr}"}>{filter.label}</label>
                <%= case filter.type do %>
                  <% :text -> %>
                    <input class="sidebar-text-input" type="text" name={filter.attr} id={"input_#{filter.attr}"} value={@current_filters[filter.attr]} phx-debounce="500" />
                  <% :select -> %>
                    <select class="sidebar-select" name={filter.attr} id={"input_#{filter.attr}"}>
                      <option :for={{label, value} <- filter.values} value={value} selected={to_string(@current_filters[filter.attr]) == value}>
                        {label}
                      </option>
                    </select>
                  <% :number -> %>
                    <input class="sidebar-text-input" type="number" name={filter.attr} id={"input_#{filter.attr}"} value={@current_filters[filter.attr]} phx-debounce="100" />
                <% end %>
              </div>
            </form>
          </div>
        </div>

        <div class="border-base-700 mb-14 flex h-16 shrink-0 justify-end border-t p-4">
          <button class="sidebar-button" type="button" phx-click={@on_reset}>Reset Filters</button>
        </div>
      </div>
    </div>
    """
  end
end
