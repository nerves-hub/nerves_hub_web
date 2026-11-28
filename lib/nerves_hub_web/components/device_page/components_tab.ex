defmodule NervesHubWeb.Components.DevicePage.ComponentsTab do
  @moduledoc """
  What the device is connected to, from its `components` snapshots: a
  microcontroller on a UART, Zigbee and Z-Wave nodes, a USB peripheral.

  Components are grouped by namespace, missing ones first in each group, and
  shown as rows or as cards by the user's `component_view` preference. A row
  or card opens a side panel (`?component=<id>`) with why it is missing, what
  it is, what has happened to it, and the two things a person can do about a
  missing one: ask the device to look again, or forget it.

  The list re-reads whenever a snapshot changes something
  (`components:updated`), which is rare, so there is no batching here as the
  Errors tab needs.

  The extension reports only whether a component is there, so a component is
  Working or Missing. Error and Warning come in a later version.
  """

  use NervesHubWeb, tab_component: :components

  alias NervesHub.Accounts
  alias NervesHub.Accounts.User.DisplayPreferences
  alias NervesHub.Devices.Components
  alias NervesHub.Devices.DeviceComponent
  alias NervesHubWeb.Components.DateTimes
  alias NervesHubWeb.Components.DevicePage.TabNotice
  alias NervesHubWeb.Components.Fleet

  def tab_params(params, _uri, socket) do
    socket
    |> assign_new(:component_filter, fn -> :all end)
    |> load_components()
    |> select_component(params["component"])
    |> cont()
  end

  # Only assigns this tab alone owns. `:component_missing_count` is the page's,
  # since the tab's dot reads it on every tab.
  def cleanup() do
    [:components, :component_filter, :selected_component, :component_history]
  end

  defp load_components(socket) do
    components = Components.list_for_device(socket.assigns.device)

    socket
    |> assign(:components, components)
    |> assign(:component_missing_count, Enum.count(components, &(DeviceComponent.status(&1) == :missing)))
  end

  defp select_component(socket, nil) do
    socket
    |> assign(:selected_component, nil)
    |> assign(:component_history, nil)
  end

  defp select_component(socket, id) do
    case Enum.find(socket.assigns.components, &(to_string(&1.id) == id)) do
      nil ->
        select_component(socket, nil)

      component ->
        socket
        |> assign(:selected_component, component)
        |> assign(:component_history, nil)
        |> start_async(:component_history, fn -> Components.history(component) end)
    end
  end

  def hooked_async(:component_history, {:ok, history}, socket) do
    socket
    |> assign(:component_history, history)
    |> halt()
  end

  # ClickHouse not answering leaves the Recent list empty rather than the
  # panel broken.
  def hooked_async(:component_history, {:exit, _reason}, socket) do
    socket
    |> assign(:component_history, [])
    |> halt()
  end

  def hooked_async(_name, _result, socket), do: {:cont, socket}

  @decorate requires_membership()
  def hooked_event("set-component-view", %{"view" => view}, socket) do
    scope = socket.assigns.current_scope

    case Accounts.update_user_component_view(scope.user, view) do
      {:ok, user} -> socket |> assign(:current_scope, %{scope | user: user}) |> halt()
      {:error, _changeset} -> halt(socket)
    end
  end

  @decorate requires_membership()
  def hooked_event("set-component-filter", %{"filter" => filter}, socket) when filter in ["all", "attention"] do
    socket
    |> assign(:component_filter, String.to_existing_atom(filter))
    |> halt()
  end

  @decorate requires_membership()
  def hooked_event("close-component", _params, socket) do
    socket
    |> push_patch(to: tab_path(socket))
    |> halt()
  end

  # ↑ and ↓ step through the components the list shows, in its order.
  @decorate requires_membership()
  def hooked_event("step-component", %{"by" => by}, socket) when by in ["-1", "1"] do
    %{components: components, component_filter: filter, selected_component: selected} = socket.assigns
    shown = components |> groups(filter) |> Enum.flat_map(&elem(&1, 1))

    case selected && Enum.find_index(shown, &(&1.id == selected.id)) do
      nil ->
        halt(socket)

      index ->
        next = Enum.at(shown, max(index + String.to_integer(by), 0)) || Enum.at(shown, index)

        socket
        |> push_patch(to: tab_path(socket) <> "?component=#{next.id}", replace: true)
        |> halt()
    end
  end

  @decorate requires_permission(:"device:update")
  def hooked_event("refresh-components", _params, socket) do
    :ok = Components.request_refresh(socket.assigns.device)

    socket
    |> put_flash(:info, "Asked the device to look again.")
    |> halt()
  end

  @decorate requires_permission(:"device:update")
  def hooked_event("forget-component", %{"id" => id}, socket) do
    %{device: device, current_scope: scope} = socket.assigns

    with %DeviceComponent{} = component <- Components.get_for_device(device, id),
         :ok <- Components.forget(device, component.id, scope.user.name) do
      socket
      |> put_flash(:info, "Forgot #{DeviceComponent.display_name(component)}.")
      |> push_patch(to: tab_path(socket))
      |> halt()
    else
      _ -> socket |> put_flash(:error, "That component has already gone.") |> halt()
    end
  end

  @decorate requires_no_permission()
  def hooked_event(_event, _params, socket), do: {:cont, socket}

  # Re-read, and keep the panel on the same component if it is still there.
  # Halts: the page's own clause only recounts the tab's dot, which
  # `load_components/1` has just done.
  def hooked_info(%Broadcast{event: "components:updated"}, socket) do
    selected = socket.assigns[:selected_component]

    socket
    |> load_components()
    |> then(fn socket ->
      case selected && Enum.find(socket.assigns.components, &(&1.id == selected.id)) do
        nil -> assign(socket, :selected_component, nil)
        component -> assign(socket, :selected_component, component)
      end
    end)
    |> halt()
  end

  def hooked_info(_message, socket), do: {:cont, socket}

  defp tab_path(socket) do
    %{org: org, product: product, device: device} = socket.assigns
    ~p"/org/#{org}/#{product}/devices/#{device}/components"
  end

  def render(%{product: %{extensions: %{components: false}}} = assigns) do
    ~H"""
    <TabNotice.render title="Components aren't enabled for this product." detail="Please check the product settings." />
    """
  end

  def render(%{device: %{extensions: %{components: false}}} = assigns) do
    ~H"""
    <TabNotice.render title="Components aren't enabled for this device." detail="Please check the device settings." />
    """
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign(:view, DisplayPreferences.component_view(assigns.current_scope.user.display_preferences))
      |> assign(:groups, groups(assigns.components, assigns.component_filter))
      |> assign(:base, ~p"/org/#{assigns.org}/#{assigns.product}/devices/#{assigns.device}/components")
      |> assign(:device_seen, assigns[:device_connection] && assigns.device_connection.last_seen_at)

    ~H"""
    <div id="components-tab" class="tab-content flex w-full flex-col gap-4 p-4 sm:p-6">
      <div class="flex flex-wrap items-center justify-between gap-x-4 gap-y-2">
        <div class="flex items-center gap-1.5">
          <button
            :for={{filter, label, count} <- [{:all, "All", length(@components)}, {:attention, "Needs attention", @component_missing_count}]}
            type="button"
            phx-click="set-component-filter"
            phx-value-filter={filter}
            aria-pressed={to_string(@component_filter == filter)}
            class="flex h-7 cursor-pointer items-center gap-1.5 rounded border border-line-default bg-surface-raised px-2.5 text-xs font-medium text-content-body aria-pressed:border-transparent aria-pressed:bg-content-strong aria-pressed:text-surface-raised"
          >
            <span :if={filter == :attention and count > 0} class="size-1.5 rounded-full bg-alert"></span>
            {label} <span class="text-content-faint">{count}</span>
          </button>
        </div>
        <div role="group" aria-label="View" class="flex h-7 shrink-0 overflow-hidden rounded border border-line-control bg-surface-raised max-sm:hidden">
          <button
            :for={{value, icon, label} <- [{:list, "lucide-list", "List"}, {:grid, "lucide-layout-grid", "Grid"}]}
            type="button"
            phx-click="set-component-view"
            phx-value-view={value}
            aria-pressed={to_string(@view == value)}
            aria-label={label}
            title={label}
            class="flex w-7 cursor-pointer items-center justify-center text-content-faint not-last:border-r not-last:border-line-control hover:text-content-strong aria-pressed:bg-line-subtle aria-pressed:text-content-strong"
          >
            <span class={[icon, "size-3.5"]} aria-hidden="true"></span>
          </button>
        </div>
      </div>

      <div
        :if={@components == []}
        class="flex flex-col items-center justify-center gap-1 rounded-card border border-line-default bg-surface-raised p-14 text-center"
      >
        <span class="text-ui text-content-body">No components yet.</span>
        <span class="text-xs text-content-faint">They show here once the device sends its first components snapshot.</span>
      </div>

      <div :if={@components != [] and @groups == []} class="flex items-center justify-center rounded-card border border-line-default bg-surface-raised p-14">
        <span class="text-ui text-content-faint">Nothing needs attention.</span>
      </div>

      <div :if={@groups != [] and @view == :list} class="overflow-clip rounded-card border border-line-default bg-surface-raised shadow-card">
        <.list_view groups={@groups} base={@base} selected={@selected_component} device_seen={@device_seen} time_zone={@time_zone} />
      </div>
      <.grid_view
        :if={@groups != [] and @view == :grid}
        groups={@groups}
        base={@base}
        selected={@selected_component}
        device_seen={@device_seen}
        time_zone={@time_zone}
      />

      <.panel
        :if={@selected_component}
        component={@selected_component}
        history={@component_history}
        device={@device}
        current_scope={@current_scope}
        time_zone={@time_zone}
      />
    </div>
    """
  end

  attr(:groups, :list, required: true)
  attr(:base, :string, required: true)
  attr(:selected, :any, required: true)
  attr(:device_seen, :any, required: true)
  attr(:time_zone, :string, required: true)

  defp list_view(assigns) do
    ~H"""
    <div class="overflow-x-auto max-sm:overflow-visible">
      <table id="components-list" class="w-full min-w-3xl table-fixed text-left max-sm:block max-sm:min-w-0">
        <colgroup class="max-sm:hidden">
          <col class="w-36" />
          <col />
          <col class="w-56" />
          <col class="w-36" />
          <col class="w-32" />
          <col class="w-10" />
        </colgroup>
        <thead class="max-sm:hidden">
          <tr class="text-label text-content-faint uppercase">
            <th class="h-8 px-4 font-medium">Status</th>
            <th class="h-8 pr-4 font-medium">Component</th>
            <th class="h-8 pr-4 font-medium">Serial</th>
            <th class="h-8 pr-4 font-medium">Firmware</th>
            <th class="h-8 pr-4 font-medium">Last seen</th>
            <th class="h-8"><span class="sr-only">Details</span></th>
          </tr>
        </thead>
        <tbody :for={{namespace, components} <- @groups} class="max-sm:block">
          <tr class="border-t border-line-subtle bg-surface-muted max-sm:block">
            <td colspan="6" class="h-8 px-4 text-xs text-content-muted max-sm:flex max-sm:items-center">
              <.group_heading namespace={namespace} components={components} />
            </td>
          </tr>
          <tr
            :for={component <- components}
            id={"component-#{component.id}"}
            phx-click={JS.patch("#{@base}?component=#{component.id}")}
            class={[
              "h-15 cursor-pointer border-t border-line-subtle hover:bg-surface-muted",
              "max-sm:grid max-sm:h-auto max-sm:grid-cols-[minmax(0,1fr)_auto] max-sm:gap-1.5 max-sm:px-4 max-sm:py-3",
              @selected && @selected.id == component.id && "bg-surface-muted shadow-[inset_2px_0_0_var(--color-content-muted)]"
            ]}
          >
            <td class="px-4 max-sm:p-0"><.status_badge component={component} /></td>
            <td class="py-2.5 pr-4 max-sm:col-span-2 max-sm:p-0">
              <div class={["truncate text-ui/4 font-medium", if(missing?(component), do: "text-content-muted", else: "text-content-strong")]}>
                {DeviceComponent.display_name(component)}
              </div>
              <div class="truncate pt-0.75 text-xs text-content-muted">{subtitle(component)}</div>
              <div :if={missing?(component)} class="truncate pt-0.75 text-xs text-content-body">
                {missing_line(component, @time_zone)}
              </div>
            </td>
            <td
              class={["truncate pr-4 font-mono text-xs max-sm:hidden", if(missing?(component), do: "text-content-faint", else: "text-content-body")]}
              title={component.serial}
            >
              {component.serial}
            </td>
            <td class={["truncate pr-4 font-mono text-xs max-sm:hidden", if(missing?(component), do: "text-content-faint", else: "text-content-strong")]}>
              {DeviceComponent.firmware_version(component) || "—"}
            </td>
            <td class="pr-4 text-xs text-content-muted max-sm:hidden">{last_seen(component, @device_seen)}</td>
            <td class="max-sm:col-start-2 max-sm:row-start-1">
              <.link patch={"#{@base}?component=#{component.id}"} class="flex text-content-faint hover:text-content-body">
                <span class="lucide-chevron-right size-4" aria-hidden="true"></span>
                <span class="sr-only">Details for {DeviceComponent.display_name(component)}</span>
              </.link>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr(:groups, :list, required: true)
  attr(:base, :string, required: true)
  attr(:selected, :any, required: true)
  attr(:device_seen, :any, required: true)
  attr(:time_zone, :string, required: true)

  defp grid_view(assigns) do
    ~H"""
    <div id="components-grid" class="flex flex-col gap-5">
      <section :for={{namespace, components} <- @groups} class="flex flex-col gap-2.5">
        <div class="text-ui text-content-muted"><.group_heading namespace={namespace} components={components} /></div>
        <div class="grid grid-cols-1 gap-3 md:grid-cols-2 lg:grid-cols-3">
          <.link
            :for={component <- components}
            id={"component-card-#{component.id}"}
            patch={"#{@base}?component=#{component.id}"}
            class={[
              "flex min-w-0 flex-col gap-3.5 rounded-card border px-4 py-3.5 hover:border-line-strong",
              if(missing?(component), do: "border-dashed border-line-strong", else: "border-line-default bg-surface-raised shadow-card"),
              @selected && @selected.id == component.id && "ring-2 ring-focus-ring"
            ]}
          >
            <div class="flex items-center justify-between gap-2">
              <.status_badge component={component} />
              <span class="text-xs text-content-faint">{last_seen(component, @device_seen)}</span>
            </div>
            <div class="flex min-w-0 flex-col gap-0.75">
              <span class={["truncate text-sm/5 font-medium", if(missing?(component), do: "text-content-muted", else: "text-content-strong")]}>
                {DeviceComponent.display_name(component)}
              </span>
              <span class="truncate text-xs text-content-muted">{subtitle(component)}</span>
              <span :if={missing?(component)} class="truncate pt-2 text-xs text-content-body">{missing_line(component, @time_zone)}</span>
            </div>
            <div class={[
              "flex min-w-0 items-center gap-2 border-t border-line-subtle pt-2.5 font-mono text-xs",
              if(missing?(component), do: "text-content-faint", else: "text-content-body")
            ]}>
              <span>{DeviceComponent.firmware_version(component) || "—"}</span>
              <span class="text-content-faint" aria-hidden="true">·</span>
              <span class={["truncate", !missing?(component) && "text-content-muted"]}>{component.serial}</span>
            </div>
          </.link>
        </div>
      </section>
    </div>
    """
  end

  attr(:namespace, :string, required: true)
  attr(:components, :list, required: true)

  defp group_heading(assigns) do
    ~H"""
    <span class="font-semibold text-content-strong">{DeviceComponent.namespace_label(@namespace)}</span>
    <span class="ml-1.5 font-mono text-2xs text-content-faint">{@namespace}</span>
    <span class="ml-1.5">· {length(@components)}</span>
    """
  end

  attr(:component, DeviceComponent, required: true)

  defp status_badge(assigns) do
    ~H"""
    <span
      :if={missing?(@component)}
      class="inline-flex h-5 items-center gap-1.25 rounded-full border border-line-default px-1.75 text-xs font-medium whitespace-nowrap text-content-muted"
    >
      <span class="size-1.5 rounded-full border border-content-faint"></span>Missing
    </span>
    <span
      :if={!missing?(@component)}
      class="inline-flex h-5 items-center gap-1.25 rounded-full bg-success-soft px-1.75 text-xs font-medium whitespace-nowrap text-success-content"
    >
      <span class="size-1.5 rounded-full bg-current"></span>Working
    </span>
    """
  end

  attr(:component, DeviceComponent, required: true)
  attr(:history, :any, required: true)
  attr(:device, :any, required: true)
  attr(:current_scope, :any, required: true)
  attr(:time_zone, :string, required: true)

  defp panel(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 bg-backdrop sm:hidden" phx-click="close-component" aria-hidden="true"></div>
    <div phx-window-keydown="step-component" phx-key="ArrowUp" phx-value-by="-1" class="hidden"></div>
    <div phx-window-keydown="step-component" phx-key="ArrowDown" phx-value-by="1" class="hidden"></div>
    <aside
      id="component-panel"
      aria-labelledby="component-panel-title"
      phx-window-keydown="close-component"
      phx-key="Escape"
      class={[
        "fixed top-(--topbar-height) right-0 bottom-0 z-40 flex w-150 max-w-full flex-col border-l border-line-default bg-surface-raised shadow-[-12px_0_32px_-12px_rgb(0_0_0/0.18)]",
        "max-sm:top-auto max-sm:left-0 max-sm:z-50 max-sm:max-h-[88dvh] max-sm:w-full max-sm:rounded-t-xl max-sm:border-t max-sm:border-l-0"
      ]}
    >
      <div class="min-h-0 flex-1 overflow-y-auto">
        <header class="border-b border-line-default px-6 pt-5 pb-4.5 max-sm:px-4">
          <div class="flex items-center gap-3">
            <span class={[
              "size-2 shrink-0 rounded-full",
              if(missing?(@component), do: "border border-content-faint", else: "bg-status-online")
            ]}></span>
            <h2 id="component-panel-title" class="min-w-0 truncate text-xl/6.5 font-semibold text-content-strong">
              {DeviceComponent.display_name(@component)}
            </h2>
            <.button type="button" size="sm" square aria-label="Close" title="Close" phx-click="close-component" class="ml-auto shrink-0">
              <span class="lucide-x size-3.5" aria-hidden="true"></span>
            </.button>
          </div>
          <p class="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1 pl-5 text-ui/4 text-content-muted">
            <span :if={missing?(@component)}>
              <span class="font-medium text-content-body">Missing</span> for {since(@component.missing_since)}
            </span>
            <span :if={!missing?(@component)} class="font-medium text-success-content">Working</span>
            <span class="text-content-faint" aria-hidden="true">·</span>
            <span>{DeviceComponent.model_label(@component)}</span>
            <span class="text-content-faint" aria-hidden="true">·</span>
            <span class="font-mono text-xs">{@component.namespace}</span>
            <span :if={DeviceComponent.firmware_version(@component)} class="text-content-faint" aria-hidden="true">·</span>
            <span :if={DeviceComponent.firmware_version(@component)} class="font-mono text-xs">
              {DeviceComponent.firmware_version(@component)}
            </span>
          </p>
        </header>

        <section :if={missing?(@component)} id="component-why" class="border-b border-line-default px-6 py-5 max-sm:px-4">
          <p class="text-label font-medium text-content-muted uppercase">Why it needs attention</p>
          <p class="mt-1.5 text-base/5.5 font-semibold text-content-strong">{why(@component, @time_zone)}</p>
          <p class="mt-3 text-xs text-content-muted">
            A component the device can't reach, or stops listing, stays here as missing until it comes back or you forget it.
          </p>
        </section>

        <section :if={authorized?(:"device:update", @current_scope)} class="border-b border-line-default px-6 py-5 max-sm:px-4">
          <p class="text-label font-medium text-content-muted uppercase">Actions</p>
          <div class="mt-3 flex flex-wrap gap-2">
            <.button type="button" size="sm" phx-click="refresh-components">
              <span class="lucide-refresh-cw size-3.5" aria-hidden="true"></span> Ask the device to look again
            </.button>
            <.button
              type="button"
              size="sm"
              style="danger"
              phx-click="forget-component"
              phx-value-id={@component.id}
              data-confirm={"Forget #{DeviceComponent.display_name(@component)}? It comes back if the device lists it again."}
            >
              <span class="lucide-trash size-3.5" aria-hidden="true"></span> Forget component
            </.button>
          </div>
          <p class="mt-3 text-xs text-content-muted">
            Forgetting removes it from this list and from the product's counts. Its history stays, and it comes back if the device lists it again.
          </p>
        </section>

        <section class="border-b border-line-default px-6 py-5 max-sm:px-4">
          <p class="text-label font-medium text-content-muted uppercase">Identity</p>
          <dl class="mt-2 text-ui/4 [&>div]:flex [&>div]:min-h-7 [&>div]:items-center [&>div]:gap-3">
            <div>
              <dt class="w-36 shrink-0 text-content-muted">Type</dt>
              <dd class="font-mono text-xs text-content-strong">{@component.namespace}</dd>
            </div>
            <div>
              <dt class="w-36 shrink-0 text-content-muted">Vendor · model</dt>
              <dd class="flex min-w-0 items-baseline gap-2">
                <span class="truncate text-content-strong">{DeviceComponent.model_label(@component)}</span>
                <span class="truncate font-mono text-xs text-content-faint">{@component.vendor} · {@component.model}</span>
              </dd>
            </div>
            <div>
              <dt class="w-36 shrink-0 text-content-muted">Serial</dt>
              <dd class="min-w-0 font-mono text-xs break-all text-content-strong">{@component.serial}</dd>
            </div>
            <div :if={@component.address}>
              <dt class="w-36 shrink-0 text-content-muted">Address</dt>
              <dd class="text-content-strong">{@component.address}</dd>
            </div>
            <div :if={@component.hardware_revision}>
              <dt class="w-36 shrink-0 text-content-muted">Hardware revision</dt>
              <dd class="font-mono text-xs text-content-strong">{@component.hardware_revision}</dd>
            </div>
            <div>
              <dt class="w-36 shrink-0 text-content-muted">Firmware</dt>
              <dd class="font-mono text-xs text-content-strong">{DeviceComponent.firmware_version(@component) || "—"}</dd>
            </div>
            <div :for={{key, version} <- DeviceComponent.other_versions(@component)} id={"component-version-#{key}"}>
              <dt class="w-36 shrink-0 truncate font-mono text-xs text-content-muted" title={key}>{key}</dt>
              <dd class="min-w-0 font-mono text-xs break-all text-content-strong">{version}</dd>
            </div>
            <div>
              <dt class="w-36 shrink-0 text-content-muted">First seen</dt>
              <dd class="text-content-strong">{DateTimes.to_local_string(@component.first_seen_at, @time_zone, :medium_date, false)}</dd>
            </div>
          </dl>
        </section>

        <section class="px-6 py-5 max-sm:px-4">
          <p class="text-label font-medium text-content-muted uppercase">Recent</p>
          <ul :if={is_nil(@history)} class="mt-3 flex flex-col gap-3" aria-hidden="true">
            <li :for={_ <- 1..3} class="h-4 w-2/3 animate-pulse rounded bg-surface-muted"></li>
          </ul>
          <p :if={@history == []} class="mt-3 text-ui/4 text-content-faint">Nothing recorded yet.</p>
          <ul :if={@history not in [nil, []]} id="component-history" class="mt-2 flex flex-col">
            <li :for={entry <- @history} class="flex min-h-7 items-center gap-2.5">
              <span class={["size-1.5 shrink-0 rounded-full", history_dot(entry.event)]} aria-hidden="true"></span>
              <span class="min-w-0 grow truncate text-ui/4 text-content-body">{history_line(entry)}</span>
              <span class="shrink-0 font-mono text-xs whitespace-nowrap text-content-faint">
                {DateTimes.to_local_string(entry.timestamp, @time_zone, :short_datetime, false)}
              </span>
            </li>
          </ul>
        </section>
      </div>

      <footer class="flex h-10 shrink-0 items-center gap-5 border-t border-line-default px-6 text-xs text-content-muted max-sm:hidden">
        <span class="flex items-center gap-1.5"><.kbd>↑</.kbd><.kbd>↓</.kbd>
        Next component</span>
        <span class="flex items-center gap-1.5"><.kbd>esc</.kbd>
        Close</span>
      </footer>
    </aside>
    """
  end

  slot(:inner_block, required: true)

  defp kbd(assigns) do
    ~H"""
    <kbd class="inline-flex h-4.5 min-w-4.5 items-center justify-center rounded border border-line-default px-1 font-sans text-2xs/3.5 text-content-muted">
      {render_slot(@inner_block)}
    </kbd>
    """
  end

  # Grouped by namespace, in the order the list query gave, with the filter
  # applied. A namespace the filter empties isn't shown.
  defp groups(components, filter) do
    components
    |> Enum.filter(&(filter == :all or missing?(&1)))
    |> Enum.chunk_by(& &1.namespace)
    |> Enum.map(fn [first | _] = group -> {first.namespace, group} end)
  end

  defp missing?(component), do: DeviceComponent.status(component) == :missing

  # The model, and where it is on its bus when the device said.
  defp subtitle(%DeviceComponent{address: nil} = component), do: DeviceComponent.model_label(component)
  defp subtitle(component), do: "#{DeviceComponent.model_label(component)} · #{component.address}"

  defp missing_line(component, time_zone) do
    at = time(component.missing_since, time_zone)

    case DeviceComponent.missing_reason(component) do
      :unreachable -> "Can't reach it since #{at}"
      :unlisted -> "Stopped listing it at #{at}"
    end
  end

  defp why(component, time_zone) do
    heard =
      if component.last_seen_at, do: " It last heard from it at #{time(component.last_seen_at, time_zone)}.", else: ""

    case DeviceComponent.missing_reason(component) do
      :unreachable -> "The device can't reach this component." <> heard
      :unlisted -> "The device stopped listing this component at #{time(component.missing_since, time_zone)}." <> heard
    end
  end

  # "7:12 AM" today, "Nov 21, 7:12 AM" before.
  defp time(nil, _time_zone), do: "an unknown time"

  defp time(at, time_zone) do
    format = if DateTimes.day_label(at, time_zone) == "Today", do: :time, else: :short_datetime
    DateTimes.to_local_string(at, time_zone, format, false)
  end

  # The device's word where it gave a time. Otherwise, as docs/components.md
  # promises client authors, when it went missing for a missing component,
  # and when the device itself was last seen for one still working: the
  # device listed it reachable then.
  defp last_seen(%DeviceComponent{last_seen_at: %DateTime{} = at}, _device_seen), do: ago(at)

  defp last_seen(%DeviceComponent{} = component, device_seen) do
    case {DeviceComponent.status(component), component.missing_since, device_seen} do
      {:missing, %DateTime{} = at, _device_seen} -> ago(at)
      {:working, _missing_since, %DateTime{} = at} -> ago(at)
      _unknown -> "—"
    end
  end

  defp since(nil), do: "a while"
  defp since(at), do: Fleet.duration(max(DateTime.diff(DateTime.utc_now(), at), 60))

  defp ago(at) do
    case DateTime.diff(DateTime.utc_now(), at) do
      seconds when seconds < 60 -> "Just now"
      seconds -> "#{Fleet.duration(seconds)} ago"
    end
  end

  defp history_line(%{event: "appeared"}), do: "Appeared"
  defp history_line(%{event: "missing", detail: "unreachable"}), do: "Device can't reach it"
  defp history_line(%{event: "missing"}), do: "Device stopped listing it"
  defp history_line(%{event: "returned"}), do: "Came back"

  defp history_line(%{event: "version_changed", version_key: key, detail: from, versions: versions}),
    do: "#{version_label(key)} #{from} → #{Map.get(versions, key, "?")}"

  defp history_line(%{event: "forgotten", detail: ""}), do: "Forgotten"
  defp history_line(%{event: "forgotten", detail: who}), do: "Forgotten by #{who}"
  defp history_line(%{event: event}), do: event

  defp version_label("firmware"), do: "Firmware"
  defp version_label(key), do: key

  defp history_dot("missing"), do: "border border-content-faint"
  defp history_dot("returned"), do: "bg-status-online"
  defp history_dot("version_changed"), do: "bg-primary"
  defp history_dot(_event), do: "bg-content-faint"
end
