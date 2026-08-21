defmodule NervesHubWeb.Components.CommandPalette do
  @moduledoc """
  The CMD-K command palette, rendered once per authenticated page.

  Opening, keyboard navigation and closing are handled client side by the
  `CommandPalette` JS hook. Typing in the search box round-trips to the server
  (`handle_event("search", ...)`), which queries `NervesHub.CommandPalette`
  asynchronously (via `assign_async/3`, so the DB lookups never block the
  LiveView) and renders grouped results plus a set of static navigation
  commands. The static commands don't hit the DB, so they render immediately.
  """

  use NervesHubWeb, :live_component

  alias NervesHub.CommandPalette
  alias Phoenix.LiveView.AsyncResult

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> assign_new(:open, fn -> false end)
    |> assign_new(:query, fn -> "" end)
    |> assign_new(:results, fn -> AsyncResult.ok(empty_results()) end)
    |> ok()
  end

  # Open/close is owned by the server so re-renders (every keystroke fires
  # phx-change) don't clobber a client-toggled `hidden` class and snap it shut.
  @impl Phoenix.LiveComponent
  def handle_event("open", _params, socket) do
    socket
    |> assign(:open, true)
    |> noreply()
  end

  def handle_event("close", _params, socket) do
    socket
    |> assign(:open, false)
    |> assign(:query, "")
    |> assign(:results, AsyncResult.ok(empty_results()))
    |> noreply()
  end

  def handle_event("search", %{"query" => query}, socket) do
    scope = socket.assigns.current_scope

    socket
    |> assign(:query, query)
    |> assign_async(:results, fn ->
      {:ok, %{results: CommandPalette.search(scope, query)}}
    end)
    |> noreply()
  end

  defp empty_results(), do: %{devices: [], deployment_groups: [], firmware: []}

  @impl Phoenix.LiveComponent
  def render(assigns) do
    assigns = assign(assigns, :commands, matching_commands(assigns.current_scope, assigns.query))

    ~H"""
    <div id={@id} phx-hook="CommandPalette">
      <div data-palette-overlay class={["relative z-50", not @open && "hidden"]} role="dialog" aria-modal="true" aria-label="Command palette">
        <div data-palette-backdrop class="bg-base-200/90 fixed inset-0 transition-opacity" aria-hidden="true"></div>
        <div class="fixed inset-0 overflow-y-auto p-4 sm:p-6 md:p-20">
          <div class="bg-surface-overlay border-base-700 ring-base-700/10 mx-auto max-w-2xl overflow-hidden rounded-xl border shadow-2xl ring-1">
            <form id="command-palette-form" phx-change="search" phx-target={@myself} phx-debounce="150" autocomplete="off">
              <div class="border-base-700 flex items-center gap-3 border-b px-4">
                <span class="lucide-search--light text-base-400 size-5 shrink-0"></span>
                <label for="command-palette-input" class="sr-only">Search devices, deployment groups, firmware</label>
                <input
                  type="text"
                  id="command-palette-input"
                  name="query"
                  data-palette-input
                  role="combobox"
                  aria-expanded="true"
                  aria-controls="command-palette-results"
                  spellcheck="false"
                  placeholder="Search devices, deployment groups, firmware…"
                  class="placeholder:text-base-500 text-base-50 h-12 w-full border-0 bg-transparent text-sm focus:ring-0 focus:outline-none"
                />
                <kbd class="border-base-700 text-base-400 hidden rounded border px-1.5 py-0.5 text-xs sm:inline-block">esc</kbd>
              </div>
            </form>

            <div id="command-palette-results" data-palette-results role="listbox" class="scrollbar-thin scrollbar-thumb-base-800 max-h-96 overflow-y-auto py-2">
              <.async_result :let={results} assign={@results}>
                <:loading>
                  <div class="text-base-500 px-4 py-6 text-center text-sm">Searching…</div>
                </:loading>
                <:failed :let={_failure}>
                  <div class="text-base-500 px-4 py-6 text-center text-sm">Something went wrong while searching.</div>
                </:failed>

                <.result_group :if={results.devices != []} title="Devices">
                  <.result_item
                    :for={device <- results.devices}
                    navigate={~p"/org/#{device.org_name}/#{device.product_name}/devices/#{device.identifier}"}
                    icon="lucide-cpu--light"
                    label={device.identifier}
                    hint={"#{device.org_name} / #{device.product_name}"}
                  />
                </.result_group>

                <.result_group :if={results.deployment_groups != []} title="Deployment Groups">
                  <.result_item
                    :for={group <- results.deployment_groups}
                    navigate={~p"/org/#{group.org_name}/#{group.product_name}/deployment_groups/#{group.id}"}
                    icon="lucide-rocket--light"
                    label={group.name}
                    hint={"#{group.org_name} / #{group.product_name}"}
                  />
                </.result_group>

                <.result_group :if={results.firmware != []} title="Firmware">
                  <.result_item
                    :for={firmware <- results.firmware}
                    navigate={~p"/org/#{firmware.org_name}/#{firmware.product_name}/firmware/#{firmware.uuid}"}
                    icon="lucide-binary--light"
                    label={firmware.uuid}
                    hint={"#{firmware.version} · #{firmware.product_name}"}
                  />
                </.result_group>

                <div
                  :if={results.devices == [] and results.deployment_groups == [] and results.firmware == [] and @commands == []}
                  class="text-base-500 px-4 py-6 text-center text-sm"
                >
                  <span :if={String.trim(@query) == ""}>Type to search devices, deployment groups and firmware.</span>
                  <span :if={String.trim(@query) != ""}>No results for &ldquo;{@query}&rdquo;.</span>
                </div>
              </.async_result>

              <.result_group :if={@commands != []} title="Navigation">
                <.result_item
                  :for={command <- @commands}
                  navigate={command.path}
                  icon={command.icon}
                  label={command.label}
                />
              </.result_group>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr(:title, :string, required: true)
  slot(:inner_block, required: true)

  defp result_group(assigns) do
    ~H"""
    <div class="px-2 pb-2">
      <div class="text-base-500 px-2 pt-2 pb-1 text-xs font-semibold tracking-wide uppercase">{@title}</div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr(:navigate, :string, required: true)
  attr(:icon, :string, required: true)
  attr(:label, :string, required: true)
  attr(:hint, :string, default: nil)

  defp result_item(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      data-palette-item
      role="option"
      class="hover:bg-primary/20 text-base-200 flex items-center gap-3 rounded-md p-2 text-sm"
    >
      <span class={["text-base-400 size-4 shrink-0", @icon]}></span>
      <span class="min-w-0 flex-1 truncate">{@label}</span>
      <span :if={@hint} class="text-base-500 shrink-0 truncate text-xs">{@hint}</span>
    </.link>
    """
  end

  # Static navigation commands available for the current scope, filtered by the
  # search term. Product-scoped commands only appear when a product is active.
  defp matching_commands(scope, query) do
    scope
    |> commands()
    |> filter_commands(query)
  end

  defp commands(%{product: product, org: org}) when not is_nil(product) and not is_nil(org) do
    o = org.name
    p = product.name

    [
      %{label: "Devices", path: ~p"/org/#{o}/#{p}/devices", icon: "lucide-cpu--light"},
      %{label: "Deployment Groups", path: ~p"/org/#{o}/#{p}/deployment_groups", icon: "lucide-rocket--light"},
      %{label: "Firmware", path: ~p"/org/#{o}/#{p}/firmware", icon: "lucide-binary--light"},
      %{label: "Archives", path: ~p"/org/#{o}/#{p}/archives", icon: "lucide-archive--light"},
      %{label: "Support Scripts", path: ~p"/org/#{o}/#{p}/scripts", icon: "lucide-file-code-corner--light"},
      %{label: "Product Settings", path: ~p"/org/#{o}/#{p}/settings", icon: "lucide-settings--light"}
    ] ++ org_commands(org)
  end

  defp commands(%{org: org}) when not is_nil(org), do: org_commands(org)

  defp commands(_scope), do: []

  defp org_commands(org) do
    o = org.name

    [
      %{label: "Products", path: ~p"/org/#{o}", icon: "lucide-package--light"},
      %{label: "Users", path: ~p"/org/#{o}/settings/users", icon: "lucide-users--light"},
      %{label: "Signing Keys", path: ~p"/org/#{o}/settings/keys", icon: "lucide-key-round--light"},
      %{label: "Organization Settings", path: ~p"/org/#{o}/settings", icon: "lucide-settings--light"}
    ]
  end

  defp filter_commands(commands, query) do
    case String.trim(query) do
      "" ->
        []

      term ->
        term = String.downcase(term)
        Enum.filter(commands, &String.contains?(String.downcase(&1.label), term))
    end
  end
end
