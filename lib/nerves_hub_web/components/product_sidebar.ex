defmodule NervesHubWeb.Components.ProductSidebar do
  @moduledoc """
  The product half of a product page's sidebar: its header, switcher and page links.

  The header names the organization and product and counts devices online. Devices
  shows unhealthy devices (or, failing that, warnings), Deployment groups the group
  count and any release awaiting approval, Errors the open issues and Notifications
  the total. Offline devices are never shown, since every product has some. On the
  rail a dot or count on the icon stands in for the line, and a tooltip spells it
  out. Figures are counted synchronously when the product changes, so links don't
  shift as they arrive, and they never update live. The one exception is the
  notifications count on the notifications page, which follows notifications
  arriving and being dismissed there; that page sends it with `send_update/3`
  (`notifications_count:`). The switcher's figures for every
  product in the organization are counted only when it opens. A member who sees only
  some devices gets none of the product-wide pages or figures, except the online
  count, which covers only the devices they can see. The root carries
  `data-attention` with the most severe status, which the phone top bar's menu
  button shows as a dot (see `app.css`).
  """
  use NervesHubWeb, :live_component

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Scope
  alias NervesHub.Devices.Health
  alias NervesHub.ErrorReports
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Workflows
  alias NervesHub.ProductNotifications
  alias NervesHub.Products
  alias NervesHubWeb.Components.Fleet
  alias Phoenix.LiveView.JS

  @no_health %{healthy: 0, warning: 0, unhealthy: 0}

  @impl Phoenix.LiveComponent
  def update(%{notifications_count: count}, socket) do
    socket =
      if socket.assigns[:status][:every_device?] do
        socket
        |> assign(:status, Map.put(socket.assigns.status, :notifications, count))
        |> then(&assign(&1, :attention, attention(&1.assigns.status)))
      else
        socket
      end

    {:ok, socket}
  end

  def update(assigns, socket) do
    product_changed? = socket.assigns[:product_id] != assigns.current_scope.product.id

    socket
    |> assign(assigns)
    |> assign(:product_id, assigns.current_scope.product.id)
    |> assign_new(:switcher_open, fn -> false end)
    |> assign_new(:switcher, fn -> nil end)
    |> assign_new(:query, fn -> "" end)
    |> then(fn socket ->
      if product_changed?, do: assign(socket, :status, load_status(assigns.current_scope)), else: socket
    end)
    |> then(&assign(&1, :attention, attention(&1.assigns.status)))
    |> ok()
  end

  @impl Phoenix.LiveComponent
  @decorate requires_membership()
  def handle_event("open_switcher", _params, socket) do
    socket
    |> assign(:switcher_open, true)
    |> assign(:query, "")
    |> assign(:switcher, load_switcher(socket.assigns.current_scope))
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("close_switcher", _params, socket) do
    socket
    |> assign(:switcher_open, false)
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("filter_switcher", %{"query" => query}, socket) do
    socket
    |> assign(:query, query)
    |> noreply()
  end

  @page_labels %{
    insights: "Insights",
    devices: "Devices",
    deployments: "Deployment groups",
    firmware: "Firmware",
    archives: "Archives",
    support_scripts: "Support scripts",
    errors: "Errors",
    notifications: "Notifications",
    settings: "Product settings"
  }

  @doc """
  The label of the sidebar link that a page's `sidebar_tab` selects.

  A phone's top bar shows it after the product name. `nil` for a tab with no link.
  """
  @spec page_label(atom() | nil) :: String.t() | nil
  def page_label(tab), do: Map.get(@page_labels, tab)

  ## Figures

  # Everything the links show for the scope's product.
  defp load_status(%Scope{product: product} = scope) do
    online = Products.get_product_counts(scope, product.id)

    if Scope.devices_limited?(scope) do
      %{
        every_device?: false,
        online: online,
        health: @no_health,
        deployment_groups: nil,
        approvals: [],
        errors: nil,
        notifications: nil
      }
    else
      %{
        every_device?: true,
        online: online,
        health: Map.get(Health.status_counts_by_product([product.id]), product.id, @no_health),
        deployment_groups: Map.get(ManagedDeployments.count_by_product([product.id]), product.id, 0),
        approvals: Workflows.awaiting_approval_in_products([product.id]),
        errors: if(product.extensions.error_reports, do: ErrorReports.status_counts(product).unresolved),
        notifications: ProductNotifications.count(product)
      }
    end
  end

  # Every product in the scope's organization, with what its row shows.
  defp load_switcher(%Scope{org: org, user: user} = scope) do
    products =
      Enum.find_value(user.orgs, [], fn user_org -> user_org.id == org.id && user_org.products end)
      |> Enum.sort_by(&String.downcase(&1.name))

    ids = Enum.map(products, & &1.id)
    %{products: online} = Accounts.get_org_device_counts(scope, org.id)

    {health, errors} =
      if Scope.devices_limited?(scope) do
        {%{}, %{}}
      else
        with_errors = for product <- products, product.extensions.error_reports, do: product.id
        {Health.status_counts_by_product(ids), ErrorReports.unresolved_counts_by_product(with_errors)}
      end

    rows =
      for product <- products do
        %{
          product: product,
          online: Map.get(online, product.id, {0, 0}),
          health: Map.get(health, product.id, @no_health),
          errors: Map.get(errors, product.id, 0)
        }
      end

    other_orgs =
      user.orgs
      |> Enum.reject(&(&1.id == org.id))
      |> Enum.sort_by(&String.downcase(&1.name))

    %{rows: rows, other_orgs: other_orgs, every_device?: not Scope.devices_limited?(scope)}
  end

  ## Statuses

  # What a link's line says, as `{tone, text}`, or nil when there's nothing to say.
  defp devices_status(%{every_device?: false}), do: nil
  defp devices_status(%{health: %{unhealthy: n}}) when n > 0, do: {:alert, "#{delimited(n)} unhealthy"}
  defp devices_status(%{health: %{warning: 1}}), do: {:warning, "1 warning"}
  defp devices_status(%{health: %{warning: n}}) when n > 0, do: {:warning, "#{delimited(n)} warnings"}
  defp devices_status(_status), do: nil

  defp deployments_status(%{approvals: []}), do: nil

  defp deployments_status(%{approvals: [step]}) do
    case step.deployment_release.firmware do
      %{version: version} -> {:waiting, {version, " awaiting approval"}}
      _ -> {:waiting, "1 release awaiting approval"}
    end
  end

  defp deployments_status(%{approvals: steps}), do: {:waiting, "#{length(steps)} releases awaiting approval"}

  # The most severe status any link shows, for the menu button's dot. Open
  # errors count as an alert; notifications are news, not a problem.
  defp attention(status) do
    tones = [
      elem(devices_status(status) || {nil, nil}, 0),
      elem(deployments_status(status) || {nil, nil}, 0),
      if((status.errors || 0) > 0, do: :alert)
    ]

    Enum.find([:alert, :warning, :waiting], &(&1 in tones))
  end

  # A switcher row's line: its health, then its open errors, in the colour of
  # the worse of the two, where open errors count as an alert. A member who sees
  # only some devices gets no line, since seeing none of a product's devices
  # doesn't mean it has none.
  defp product_line(_row, false), do: nil
  defp product_line(%{online: {0, 0}}, true), do: {:none, "No devices yet"}

  defp product_line(row, true) do
    errors = if row.errors > 0, do: "#{delimited(row.errors)} open #{if row.errors == 1, do: "error", else: "errors"}"

    case {devices_status(%{every_device?: true, health: row.health}), errors} do
      {nil, nil} when row.health.healthy > 0 -> {:success, "Healthy"}
      {nil, nil} -> {:none, "Not reported"}
      {nil, errors} -> {:alert, errors}
      {{tone, text}, nil} -> {tone, text}
      {{_tone, text}, errors} -> {:alert, "#{text} · #{errors}"}
    end
  end

  defp matches?(_name, ""), do: true
  defp matches?(name, query), do: String.contains?(String.downcase(name), String.downcase(String.trim(query)))

  defp delimited(number), do: Fleet.delimited(number)

  defp online_percent({0, 0}), do: "—"
  defp online_percent(counts), do: "#{Fleet.online_percent(counts)}%"

  # The product's first two letters, for the tile that stands in for it on the rail.
  defp monogram(name), do: name |> String.slice(0, 2) |> String.downcase()

  defp tone_dot(:alert), do: "bg-alert"
  defp tone_dot(:warning), do: "bg-warning"
  defp tone_dot(:waiting), do: "bg-waiting"
  defp tone_dot(:success), do: "bg-success"
  defp tone_dot(:none), do: "border border-content-faint"

  defp tone_text(:alert), do: "text-alert-content"
  defp tone_text(:warning), do: "text-warning-content"
  defp tone_text(:waiting), do: "text-waiting-content"
  defp tone_text(:success), do: "text-content-muted"
  defp tone_text(:none), do: "text-content-faint"

  # The same tones on the tooltip, which is dark in both themes.
  defp tooltip_text(:alert), do: "text-red-300"
  defp tooltip_text(:warning), do: "text-amber-300"
  defp tooltip_text(:waiting), do: "text-sky-300"

  ## Rendering

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id={@id} class="relative flex min-h-0 flex-col" data-attention={@attention}>
      <.product_header scope={@current_scope} status={@status} myself={@myself} switcher_open={@switcher_open} />

      <.switcher :if={@switcher_open && @switcher} scope={@current_scope} switcher={@switcher} query={@query} myself={@myself} />

      <nav id="navigation" aria-label={"#{@current_scope.product.name} pages"} class="flex grow flex-col py-2">
        <ul role="list" class="flex flex-col">
          <.nav_link
            :if={@status.every_device?}
            id="nav-insights"
            label="Insights"
            path={~p"/org/#{@current_scope.org}/#{@current_scope.product}/insights"}
            selected={@selected_tab == :insights}
            icon="lucide-activity"
            selected_icon="lucide-activity--bold"
          />
          <.nav_link
            id="nav-devices"
            label="Devices"
            path={~p"/org/#{@current_scope.org}/#{@current_scope.product}/devices"}
            selected={@selected_tab == :devices}
            icon="lucide-cpu"
            selected_icon="lucide-cpu--bold"
            status={devices_status(@status)}
          />
          <.nav_link
            :if={@status.every_device?}
            id="nav-deployment-groups"
            label="Deployment groups"
            path={~p"/org/#{@current_scope.org}/#{@current_scope.product}/deployment_groups"}
            selected={@selected_tab == :deployments}
            icon="lucide-rocket"
            selected_icon="lucide-rocket--bold"
            status={deployments_status(@status)}
            count={@status.deployment_groups}
          />

          <.divider />

          <.nav_link
            :if={@status.every_device?}
            id="nav-firmware"
            label="Firmware"
            path={~p"/org/#{@current_scope.org}/#{@current_scope.product}/firmware"}
            selected={@selected_tab == :firmware}
            icon="lucide-binary"
            selected_icon="lucide-binary--bold"
          />
          <.nav_link
            :if={@status.every_device?}
            id="nav-archives"
            label="Archives"
            path={~p"/org/#{@current_scope.org}/#{@current_scope.product}/archives"}
            selected={@selected_tab == :archives}
            icon="lucide-archive"
            selected_icon="lucide-archive--bold"
          />
          <.nav_link
            id="nav-support-scripts"
            label="Support scripts"
            path={~p"/org/#{@current_scope.org}/#{@current_scope.product}/scripts"}
            selected={@selected_tab == :support_scripts}
            icon="lucide-file-code-corner"
            selected_icon="lucide-file-code-corner--bold"
          />

          <%= if @status.every_device? do %>
            <.divider />

            <.nav_link
              :if={@current_scope.product.extensions.error_reports}
              id="nav-errors"
              label="Errors"
              path={~p"/org/#{@current_scope.org}/#{@current_scope.product}/errors"}
              selected={@selected_tab == :errors}
              icon="lucide-circle-exclamation-point"
              selected_icon="lucide-circle-exclamation-point--bold"
              pill={(@status.errors || 0) > 0 && {:alert, "#{delimited(@status.errors)} open"}}
              rail_count={@status.errors}
            />
            <.nav_link
              id="nav-notifications"
              label="Notifications"
              path={~p"/org/#{@current_scope.org}/#{@current_scope.product}/notifications"}
              selected={@selected_tab == :notifications}
              icon="lucide-bell"
              selected_icon="lucide-bell--bold"
              pill={@status.notifications > 0 && {:neutral, delimited(@status.notifications)}}
              pill_label={Fleet.count_noun(@status.notifications, "notification", "notifications")}
            />

            <.divider />

            <.nav_link
              id="nav-settings"
              label="Product settings"
              path={~p"/org/#{@current_scope.org}/#{@current_scope.product}/settings"}
              selected={@selected_tab == :settings}
              icon="lucide-settings"
              selected_icon="lucide-settings--bold"
            />
          <% end %>
        </ul>
      </nav>
    </div>
    """
  end

  attr(:scope, Scope, required: true)
  attr(:status, :map, required: true)
  attr(:myself, :any, required: true)
  attr(:switcher_open, :boolean, required: true)

  # The organization, the product's name (which opens the switcher) and how
  # many of its devices are online. On the rail, a tile with the product's
  # first letters and the share online.
  defp product_header(assigns) do
    ~H"""
    <div class="flex shrink-0 flex-col gap-2.5 border-b border-line-default px-5 py-4 collapsed:items-center collapsed:px-0 collapsed:py-3">
      <div class="flex min-w-0 flex-col gap-0.5 collapsed:hidden">
        <.link navigate={~p"/org/#{@scope.org}"} class="group flex w-fit max-w-full items-center gap-1 text-xs/4 text-content-faint hover:text-content-body">
          <span class="truncate">{@scope.org.name}</span>
          <span class="lucide-chevron-right size-3" aria-hidden="true"></span>
        </.link>
        <button
          id="product-switcher-toggle"
          type="button"
          aria-haspopup="dialog"
          aria-expanded={to_string(@switcher_open)}
          aria-controls="product-switcher"
          phx-click={if @switcher_open, do: "close_switcher", else: "open_switcher"}
          phx-target={@myself}
          class={[
            "-mx-2 flex min-w-0 cursor-pointer items-center justify-between gap-2 rounded-md px-2 py-0.5 text-left hover:bg-surface-raised hover:shadow-card",
            @switcher_open && "bg-surface-raised shadow-card"
          ]}
        >
          <span class="truncate text-lg/6.5 font-semibold tracking-[-0.01em] text-content-strong">{@scope.product.name}</span>
          <span class="lucide-chevrons-up-down size-4 text-content-faint" aria-hidden="true"></span>
        </button>
      </div>

      <div class="flex items-center justify-between gap-2 text-xs/4 collapsed:hidden">
        <span class="flex items-center gap-1.5 text-content-muted">
          <.status_dot class="size-1.5 bg-status-online" /> Online
        </span>
        <span id="product-online" class="font-mono text-content-body tabular-nums">
          {delimited(elem(@status.online, 0))}<span class="text-content-faint"> / {delimited(elem(@status.online, 0) + elem(@status.online, 1))}</span>
        </span>
      </div>

      <button
        type="button"
        aria-label={"#{@scope.product.name}: switch product"}
        phx-click={if @switcher_open, do: "close_switcher", else: "open_switcher"}
        phx-target={@myself}
        class="hidden cursor-pointer flex-col items-center gap-1 collapsed:flex"
      >
        <span class="flex size-9 items-center justify-center rounded-lg bg-zinc-900 text-sm font-semibold text-zinc-50 dark:bg-zinc-700">
          {monogram(@scope.product.name)}
        </span>
        <span class="font-mono text-[10px]/3 text-content-faint" title="Devices online">{online_percent(@status.online)}</span>
      </button>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:label, :string, required: true)
  attr(:path, :string, required: true)
  attr(:selected, :boolean, required: true)
  attr(:icon, :string, required: true, doc: "the Lucide icon class")
  attr(:selected_icon, :string, required: true, doc: "its bold weight, for the selected link")
  attr(:status, :any, default: nil, doc: "a line under the label, as `{tone, text}`")
  attr(:count, :any, default: nil, doc: "a number at the end of the row")
  attr(:pill, :any, default: nil, doc: "a badge at the end of the row, as `{tone, text}`")
  attr(:pill_label, :string, default: nil, doc: "the badge in words, for the rail's tooltip; its text if not given")
  attr(:rail_count, :any, default: nil, doc: "a count to show on the rail's icon, in place of a dot")

  defp nav_link(assigns) do
    ~H"""
    <li id={@id} class="group/item relative">
      <.link
        navigate={@path}
        aria-current={@selected && "page"}
        class={[
          "flex min-h-10 items-center gap-3 border-l-2 border-transparent py-2 pr-5 pl-4.5 text-sm/4.5 text-content-body hover:sidebar-item-hover max-sm:min-h-11",
          "aria-[current=page]:border-primary aria-[current=page]:bg-notice-soft aria-[current=page]:font-semibold aria-[current=page]:text-content-strong aria-[current=page]:hover:bg-none",
          "collapsed:mx-auto collapsed:size-10 collapsed:min-h-0 collapsed:justify-center collapsed:rounded-md collapsed:border-l-0 collapsed:p-0"
        ]}
      >
        <span class="relative flex shrink-0 self-start pt-px collapsed:self-center collapsed:pt-0">
          <span
            class={[
              "size-4.5",
              if(@selected, do: [@selected_icon, "text-primary"], else: [@icon, "text-content-faint"])
            ]}
            aria-hidden="true"
          ></span>
          <.rail_marker status={@status} pill={@pill} count={@rail_count} />
        </span>

        <span class="flex min-w-0 flex-1 flex-col gap-0.5 collapsed:hidden">
          <span class="reserve-semibold-width flex flex-col truncate" data-label={@label}>{@label}</span>
          <span :if={@status} class={["flex items-center gap-1.5 text-xs/4 font-normal", tone_text(elem(@status, 0))]}>
            <.status_dot class={["size-1.5", tone_dot(elem(@status, 0))]} />
            <span class="truncate"><.status_text text={elem(@status, 1)} /></span>
          </span>
        </span>

        <span :if={@count} data-count class="shrink-0 self-start font-mono text-xs/4.5 font-normal text-content-faint tabular-nums collapsed:hidden">
          {delimited(@count)}
        </span>
        <.badge :if={@pill} tone={elem(@pill, 0) |> to_string()} data-count class="shrink-0 font-normal collapsed:hidden">{elem(@pill, 1)}</.badge>
      </.link>

      <%!-- Only on the rail, where the label and its line are hidden. --%>
      <span
        role="tooltip"
        class="pointer-events-none absolute top-1/2 left-full z-50 ml-2 hidden -translate-y-1/2 flex-col gap-0.5 rounded-md bg-zinc-900 px-2.5 py-1.5 text-xs/4 whitespace-nowrap text-zinc-50 shadow-overlay dark:bg-zinc-800 dark:ring-1 dark:ring-zinc-700 collapsed:group-focus-within/item:flex collapsed:group-hover/item:flex"
      >
        <span class="font-semibold">{@label}</span>
        <span :if={@status} class={["flex items-center gap-1.5", tooltip_text(elem(@status, 0))]}>
          <.status_dot class={["size-1.5", tone_dot(elem(@status, 0))]} />
          <.status_text text={elem(@status, 1)} />
        </span>
        <span :if={@pill} class={if elem(@pill, 0) == :alert, do: "text-red-300", else: "text-zinc-300"}>
          {@pill_label || elem(@pill, 1)}
        </span>
      </span>
    </li>
    """
  end

  attr(:status, :any, required: true)
  attr(:pill, :any, required: true)
  attr(:count, :any, required: true)

  # On the rail: a count on the icon where there is one, otherwise a dot in
  # the line's colour, or the brand's for a neutral badge.
  defp rail_marker(%{count: count} = assigns) when is_integer(count) and count > 0 do
    ~H"""
    <span class="absolute -top-1.5 -right-2 hidden h-3.5 min-w-3.5 items-center justify-center rounded-full bg-alert px-1 text-[9px]/3 font-semibold text-white ring-2 ring-surface-muted collapsed:flex">
      {delimited(@count)}
    </span>
    """
  end

  defp rail_marker(%{status: {tone, _text}} = assigns) do
    assigns = assign(assigns, :tone, tone)

    ~H"""
    <span class={["absolute -top-0.5 -right-0.5 hidden size-1.75 rounded-full ring-2 ring-surface-muted collapsed:block", tone_dot(@tone)]}></span>
    """
  end

  defp rail_marker(%{pill: {:neutral, _text}} = assigns) do
    ~H"""
    <span class="absolute -top-0.5 -right-0.5 hidden size-1.75 rounded-full bg-primary ring-2 ring-surface-muted collapsed:block"></span>
    """
  end

  defp rail_marker(assigns), do: ~H""

  attr(:text, :any, required: true)

  # A version reads in the monospace face: `{version, rest}`.
  defp status_text(%{text: {version, rest}} = assigns) do
    assigns = assign(assigns, version: version, rest: rest)

    ~H"""
    <span class="font-mono">{@version}</span>{@rest}
    """
  end

  defp status_text(assigns), do: ~H"{@text}"

  defp divider(assigns) do
    ~H"""
    <li role="separator" aria-hidden="true" class="mx-5 my-2 h-px bg-line-default collapsed:mx-3"></li>
    """
  end

  attr(:scope, Scope, required: true)
  attr(:switcher, :map, required: true)
  attr(:query, :string, required: true)
  attr(:myself, :any, required: true)

  # A popover beside the product's name; on a phone, a sheet from the bottom.
  defp switcher(assigns) do
    assigns =
      assigns
      |> assign(:rows, Enum.filter(assigns.switcher.rows, &matches?(&1.product.name, assigns.query)))
      |> assign(:other_orgs, Enum.filter(assigns.switcher.other_orgs, &matches?(&1.name, assigns.query)))

    ~H"""
    <div id="product-switcher" phx-window-keydown="close_switcher" phx-key="escape" phx-target={@myself}>
      <div class="fixed inset-0 z-40 bg-backdrop sm:hidden" aria-hidden="true" phx-click="close_switcher" phx-target={@myself}></div>
      <div
        role="dialog"
        aria-label="Switch product"
        phx-click-away="close_switcher"
        phx-target={@myself}
        class={[
          "z-50 flex flex-col overflow-hidden bg-surface-overlay shadow-overlay",
          "max-sm:fixed max-sm:inset-x-0 max-sm:bottom-0 max-sm:max-h-[85dvh] max-sm:rounded-t-2xl max-sm:pb-[env(safe-area-inset-bottom)]",
          "sm:absolute sm:top-17 sm:left-3 sm:max-h-[min(600px,calc(100dvh-7rem))] sm:w-90 sm:rounded-lg sm:border sm:border-line-default",
          "collapsed:top-2 collapsed:left-[calc(100%+0.5rem)]"
        ]}
      >
        <div class="flex shrink-0 items-center justify-between pt-2 pr-1.5 pl-4 sm:hidden">
          <span class="text-[17px]/6 font-semibold text-content-strong">Switch product</span>
          <button type="button" aria-label="Close" phx-click="close_switcher" phx-target={@myself} class="flex size-11 cursor-pointer items-center justify-center text-content-muted">
            <span class="lucide-x size-5" aria-hidden="true"></span>
          </button>
        </div>

        <form id="product-switcher-form" phx-change="filter_switcher" phx-submit="filter_switcher" phx-target={@myself} class="flex shrink-0 items-center gap-2 border-b border-line-subtle px-4">
          <label for="product-switcher-search" class="sr-only">Find a product</label>
          <span class="lucide-search size-4 text-content-faint" aria-hidden="true"></span>
          <input
            id="product-switcher-search"
            type="search"
            name="query"
            value={@query}
            placeholder="Find a product…"
            autocomplete="off"
            phx-debounce="100"
            phx-mounted={JS.focus()}
            class="h-11 w-full border-0 bg-transparent p-0 text-sm text-content-strong placeholder:text-content-faint focus:ring-0"
          />
        </form>

        <div class="flex min-h-0 flex-col overflow-y-auto overscroll-contain">
          <div class="flex flex-col gap-0.5 px-1.5 pt-2 pb-1.5">
            <span class="px-2.5 pb-1 text-xs/4 text-content-faint">{@scope.org.name}</span>
            <.link
              :for={row <- @rows}
              navigate={~p"/org/#{@scope.org}/#{row.product}/insights"}
              aria-current={row.product.id == @scope.product.id && "page"}
              class="flex items-center gap-2.5 rounded-md px-2.5 py-2 hover:bg-surface-muted aria-[current=page]:bg-notice-soft"
            >
              <span class="flex w-3.5 shrink-0 justify-center">
                <span :if={row.product.id == @scope.product.id} class="lucide-check size-3.5 text-primary" aria-hidden="true"></span>
              </span>
              <span class="flex min-w-0 flex-1 flex-col gap-0.5">
                <span class={["truncate text-sm/4.5 text-content-strong", row.product.id == @scope.product.id && "font-medium"]}>{row.product.name}</span>
                <.switcher_line line={product_line(row, @switcher.every_device?)} />
              </span>
              <span class="shrink-0 font-mono text-xs/4 text-content-body tabular-nums">
                <%= if row.online == {0, 0} do %>
                  <span class="text-content-faint">—</span>
                <% else %>
                  {delimited(elem(row.online, 0))}<span class="text-content-faint">/{delimited(elem(row.online, 0) + elem(row.online, 1))}</span>
                <% end %>
              </span>
            </.link>
            <p :if={@rows == []} class="px-2.5 py-2 text-sm text-content-faint">No products match.</p>
          </div>

          <div :if={@other_orgs != []} class="flex flex-col gap-0.5 border-t border-line-subtle px-1.5 pt-2 pb-1.5">
            <span class="px-2.5 pb-1 text-xs/4 text-content-faint">Other organizations</span>
            <.link :for={org <- @other_orgs} navigate={~p"/org/#{org}"} class="flex items-center gap-2.5 rounded-md px-2.5 py-2 hover:bg-surface-muted">
              <span class="flex size-5 shrink-0 items-center justify-center rounded border border-line-default text-[10px] font-semibold text-content-muted" aria-hidden="true">
                {org.name |> String.first() |> String.upcase()}
              </span>
              <span class="min-w-0 flex-1 truncate text-sm/4.5 text-content-strong">{org.name}</span>
              <span class="shrink-0 text-xs text-content-faint">{product_count(org)}</span>
              <span class="lucide-chevron-right size-3.5 text-content-faint" aria-hidden="true"></span>
            </.link>
          </div>
        </div>

        <div class="flex shrink-0 items-center justify-between border-t border-line-subtle bg-surface-muted px-4 py-2.5 text-sm/4.5 max-sm:py-3.5">
          <.link :if={authorized?(:"product:create", @scope)} navigate={~p"/org/#{@scope.org}/new"} class="flex items-center gap-1.5 text-content-body hover:text-content-strong">
            <span class="lucide-plus size-4" aria-hidden="true"></span> New product
          </.link>
          <.link navigate={~p"/org/#{@scope.org}"} class="ml-auto flex items-center gap-1 text-notice-content hover:underline">
            All of {@scope.org.name} <span class="lucide-arrow-right size-3.5" aria-hidden="true"></span>
          </.link>
        </div>
      </div>
    </div>
    """
  end

  attr(:line, :any, required: true)

  defp switcher_line(%{line: nil} = assigns), do: ~H""

  defp switcher_line(assigns) do
    assigns = assign(assigns, tone: elem(assigns.line, 0), text: elem(assigns.line, 1))

    ~H"""
    <span class={["flex items-center gap-1.5 text-xs/4", tone_text(@tone)]}>
      <.status_dot class={["size-1.5", tone_dot(@tone)]} />
      <span class="truncate">{@text}</span>
    </span>
    """
  end

  defp product_count(%{products: products}) when is_list(products),
    do: Fleet.count_noun(length(products), "product", "products")

  defp product_count(_org), do: nil
end
