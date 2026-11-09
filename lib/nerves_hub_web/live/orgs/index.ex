defmodule NervesHubWeb.Live.Orgs.Index do
  @moduledoc """
  The home page everyone lands on after signing in.

  Most people belong to one organization, so with one the page is that
  organization: its name heads the page and its products follow. With more,
  each gets a section of its own, largest first. From five up only the four
  largest get a section, and the rest share a compact table.

  Above the products sit what needs someone's attention across every
  organization (releases waiting for approval, unhealthy devices, devices
  stuck in the penalty box) and the user's pinned devices.

  Someone who belongs to no organization yet is offered a form to create
  their first organization and product instead.

  Device totals load with the page, so organizations and products can be
  sorted by size before anything renders. How many devices are online, and
  the health and attention figures, load afterwards.
  """
  use NervesHubWeb, :live_view

  import Number.Delimit, only: [number_to_delimited: 2]

  alias NervesHub.Accounts
  alias NervesHub.Devices
  alias NervesHub.Devices.Health
  alias NervesHub.Devices.Pinning
  alias NervesHub.Devices.PubSub
  alias NervesHub.Devices.Updates
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.ManagedDeployments.Workflows
  alias NervesHub.Tracker
  alias Phoenix.Socket.Broadcast

  @pinned_devices_limit 5

  # The most organizations that get a full section. Past this, the rest are
  # listed in one table, so a member of many organizations doesn't scroll past
  # every product they belong to.
  @full_sections 4

  # What a product's health counts read as before any device has reported.
  @no_health %{healthy: 0, warning: 0, unhealthy: 0}

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    if scope.user.orgs == [] do
      {:ok, assign_onboarding(socket)}
    else
      {:ok, assign_home(socket)}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("toggle-expand-devices", _, %{assigns: %{show_all_pinned?: show_all?}} = socket) do
    socket
    |> assign(:show_all_pinned?, !show_all?)
    |> noreply()
  end

  # Only keeps the address preview in step with the names. Errors come from
  # saving, so typing clears them until the next try.
  def handle_event("validate_onboarding", %{"onboarding" => params}, socket) do
    socket
    |> assign(:onboarding_form, to_form(params, as: :onboarding))
    |> noreply()
  end

  def handle_event("save_onboarding", %{"onboarding" => params}, socket) do
    user = socket.assigns.current_scope.user
    org_params = %{name: params["org_name"]}
    product_params = %{name: params["product_name"]}

    case Accounts.create_org_with_product(user, org_params, product_params) do
      {:ok, %{org: org, product: product}} ->
        socket
        |> push_navigate(to: ~p"/org/#{org}/#{product}/devices")
        |> noreply()

      {:error, step, changeset} ->
        field = if step == :org, do: :org_name, else: :product_name

        errors =
          for {_field, {message, opts}} <- changeset.errors do
            {field, {message, opts}}
          end

        socket
        |> assign(:onboarding_form, to_form(params, as: :onboarding, errors: errors, action: :insert))
        |> noreply()
    end
  end

  @impl Phoenix.LiveView
  def handle_info(%Broadcast{event: "connection:change", payload: payload}, socket) do
    update_device_statuses(socket, payload)
  end

  # Ignore unknown broadcasts
  def handle_info(%Broadcast{}, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def handle_async({:online, org_id}, {:ok, counts}, socket) do
    socket
    |> update(:online, &Map.put(&1, org_id, counts))
    |> noreply()
  end

  def handle_async(:fleet, {:ok, fleet}, socket) do
    socket
    |> assign(:fleet, fleet)
    |> assign(:attention, attention_items(socket.assigns.orgs, fleet))
    |> noreply()
  end

  # A count that failed to load stays a dash rather than taking the page down.
  def handle_async(_name, {:exit, _reason}, socket), do: {:noreply, socket}

  defp assign_onboarding(%{assigns: %{current_scope: scope}} = socket) do
    {org_name, product_name} = Accounts.generate_onboarding_names(scope.user.name)

    socket
    |> assign(:page_title, "Set up your first organization")
    |> assign(:onboarding, true)
    |> assign(:onboarding_form, to_form(%{"org_name" => org_name, "product_name" => product_name}, as: :onboarding))
  end

  defp assign_home(%{assigns: %{current_scope: scope}} = socket) do
    orgs = load_orgs(scope)
    product_ids = for entry <- orgs, %{product: product} <- entry.products, do: product.id
    pinned_devices = Pinning.get_pinned_devices(scope)

    statuses =
      Map.new(pinned_devices, fn device ->
        {device.identifier, Tracker.connection_status(device)}
      end)

    socket
    |> assign(:page_title, "Organizations")
    |> assign(:onboarding, false)
    |> assign(:orgs, orgs)
    |> assign(:online, %{})
    |> assign(:fleet, nil)
    |> assign(:attention, nil)
    |> assign(:show_all_pinned?, false)
    |> assign(:pinned_devices, pinned_devices)
    |> assign(:device_statuses, statuses)
    |> assign(:device_limit, @pinned_devices_limit)
    |> subscribe()
    |> then(fn socket ->
      Enum.reduce(orgs, socket, fn %{org: org}, acc ->
        start_async(acc, {:online, org.id}, fn -> Accounts.get_org_device_counts(scope, org.id) end)
      end)
    end)
    |> start_async(:fleet, fn -> load_fleet(product_ids) end)
  end

  # Each organization with the user's role in it, its products and their
  # device totals, largest first. Ties keep the alphabetical order the query
  # returns.
  defp load_orgs(scope) do
    orgs_with_roles = Accounts.get_orgs_with_roles(scope)
    product_ids = for {org, _role} <- orgs_with_roles, product <- org.products, do: product.id
    device_counts = Devices.count_by_product(product_ids)
    member_counts = Accounts.count_org_users_by_org(Enum.map(orgs_with_roles, fn {org, _} -> org.id end))

    orgs_with_roles
    |> Enum.map(fn {org, role} ->
      products =
        org.products
        |> Enum.map(&%{product: &1, device_count: Map.get(device_counts, &1.id, 0)})
        |> Enum.sort_by(&{-&1.device_count, &1.product.name})

      %{
        org: org,
        role: role,
        products: products,
        device_count: products |> Enum.map(& &1.device_count) |> Enum.sum(),
        member_count: Map.get(member_counts, org.id, 0)
      }
    end)
    |> Enum.sort_by(& &1.device_count, :desc)
  end

  defp load_fleet(product_ids) do
    %{
      health: Health.status_counts_by_product(product_ids),
      deployment_groups: ManagedDeployments.count_by_product(product_ids),
      approvals: Workflows.awaiting_approval_in_products(product_ids),
      failing_updates: Updates.failing_updates_by_product(product_ids)
    }
  end

  # What needs someone's attention, in the order it's shown: releases waiting
  # for approval, then unhealthy devices, then devices whose updates keep
  # failing, each in the order its organization and product are listed.
  defp attention_items(orgs, fleet) do
    products =
      for entry <- orgs, %{product: product} <- entry.products, into: %{} do
        {product.id, {entry, product}}
      end

    approvals =
      for step <- fleet.approvals,
          {entry, product} <- [products[step.deployment_release.deployment_group.product_id]] do
        %{kind: :approval, entry: entry, product: product, step: step}
      end

    listed = for entry <- orgs, %{product: product} <- entry.products, do: {entry, product}

    unhealthy =
      for {entry, product} <- listed,
          %{unhealthy: count} when count > 0 <- [Map.get(fleet.health, product.id, @no_health)] do
        %{kind: :unhealthy, entry: entry, product: product, count: count}
      end

    failing =
      for {entry, product} <- listed,
          %{count: count, blocked_until: until} <- [fleet.failing_updates[product.id]] do
        %{kind: :failing_updates, entry: entry, product: product, count: count, until: until}
      end

    approvals ++ unhealthy ++ failing
  end

  def subscribe(%{assigns: %{pinned_devices: devices}} = socket) do
    if connected?(socket) do
      Enum.each(devices, fn device ->
        PubSub.subscribe(device.id)
      end)
    end

    socket
  end

  defp update_device_statuses(
         %{assigns: %{device_statuses: statuses}} = socket,
         %{device_id: identifier, status: status} = _payload
       ) do
    socket
    |> assign(:device_statuses, Map.put(statuses, identifier, status))
    |> noreply()
  end

  defp limit_devices(devices) do
    {limited_devices, _} = Enum.split(devices, @pinned_devices_limit)

    limited_devices
  end

  # The organizations that get a section of their own, and the rest.
  defp split_sections(orgs) when length(orgs) > @full_sections, do: Enum.split(orgs, @full_sections)
  defp split_sections(orgs), do: {orgs, []}

  defp monogram(name), do: name |> String.first() |> String.upcase()

  defp delimited(nil), do: "—"
  defp delimited(number), do: number_to_delimited(number, precision: 0)

  defp count_noun(1, singular, _plural), do: "1 #{singular}"
  defp count_noun(count, _singular, plural), do: "#{delimited(count)} #{plural}"

  # `{connected, disconnected}` for a product, or nil while it loads.
  defp product_online(online, org_id, product_id) do
    case online do
      %{^org_id => %{products: products}} -> Map.get(products, product_id, {0, 0})
      _ -> nil
    end
  end

  defp org_online(online, org_id) do
    case online do
      %{^org_id => %{org: counts}} -> counts
      _ -> nil
    end
  end

  defp online_percent({connected, disconnected}) when connected + disconnected > 0,
    do: round(connected / (connected + disconnected) * 100)

  defp online_percent(_), do: 0

  defp product_health(nil, _product_id), do: nil
  defp product_health(fleet, product_id), do: Map.get(fleet.health, product_id, @no_health)

  # An organization's health is the sum of its products'.
  defp org_health(nil, _entry), do: nil

  defp org_health(fleet, entry) do
    Enum.reduce(entry.products, @no_health, fn %{product: product}, acc ->
      Map.merge(acc, product_health(fleet, product.id), fn _status, a, b -> a + b end)
    end)
  end

  defp attention_count(nil, _org_id), do: 0
  defp attention_count(attention, org_id), do: Enum.count(attention, &(&1.entry.org.id == org_id))

  defp deployment_groups_label(nil, _product_id), do: nil

  defp deployment_groups_label(fleet, product_id) do
    case Map.get(fleet.deployment_groups, product_id, 0) do
      0 -> "No deployment groups"
      count -> count_noun(count, "deployment group", "deployment groups")
    end
  end

  # Where an attention row's product sits, as its subtitle names it: just the
  # product when there's one organization, otherwise the organization too.
  defp place(%{entry: entry, product: product}, single_org?) do
    if single_org?, do: product.name, else: "#{entry.org.name} / #{product.name}"
  end

  defp release_version(%DeploymentWorkflowStep{deployment_release: %{firmware: %{version: version}}}), do: version
  defp release_version(_step), do: nil

  defp pinned_place(device, single_org?) do
    if single_org?, do: device.product.name, else: "#{device.org.name} / #{device.product.name}"
  end

  defp offline_for(%{latest_connection: %{disconnected_at: %DateTime{} = at}}) do
    "Offline " <> duration(DateTime.diff(DateTime.utc_now(), at))
  end

  defp offline_for(_device), do: "Offline"

  defp resumes_in(%DateTime{} = until) do
    "updates resume in " <> duration(DateTime.diff(until, DateTime.utc_now()))
  end

  defp duration(seconds) when seconds < 3600, do: count_noun(max(div(seconds, 60), 1), "minute", "minutes")
  defp duration(seconds) when seconds < 86_400, do: count_noun(div(seconds, 3600), "hour", "hours")
  defp duration(seconds), do: count_noun(div(seconds, 86_400), "day", "days")

  defp health_label(%{latest_health: %{status: :healthy}}), do: {"Healthy", "text-success-content"}
  defp health_label(%{latest_health: %{status: :warning}}), do: {"Warning", "text-warning-content"}
  defp health_label(%{latest_health: %{status: :unhealthy}}), do: {"Unhealthy", "text-alert-content"}
  defp health_label(_device), do: {"No health reported", "text-content-muted"}

  ## Components

  attr(:entry, :map, required: true)
  attr(:online, :map, required: true)
  attr(:fleet, :map, default: nil)

  attr(:new_product_row, :boolean,
    default: false,
    doc: "end the card with a New product row on phones, where the section header has no room for the button"
  )

  # From md up each product is one row of columns under a header. On a phone
  # there's no header: the name and health chip share the first line, and the
  # online count and meter take the full width under them.
  defp products_table(assigns) do
    ~H"""
    <div class="overflow-hidden rounded-md border border-line-default bg-surface-raised shadow-card">
      <div :if={@entry.products == []} class="flex items-center justify-between gap-4 p-4">
        <p class="text-sm text-content-muted">No products yet.</p>
        <.button :if={authorized?(:"product:create", @entry.role)} type="link" size="sm" navigate={~p"/org/#{@entry.org}/new"}>
          <span class="lucide-plus size-3.5" aria-hidden="true"></span> New product
        </.button>
      </div>
      <div :if={@entry.products != []} role="table" aria-label={"#{@entry.org.name} products"}>
        <div
          role="row"
          class="hidden items-center gap-4 border-b border-line-default bg-surface-muted px-4 py-2.5 text-xs font-medium tracking-wide text-content-muted uppercase md:flex"
        >
          <span role="columnheader" class="flex-1">Product</span>
          <span role="columnheader" class="w-94">Online</span>
          <span role="columnheader" class="w-27.5">Health</span>
          <span class="w-4" aria-hidden="true"></span>
        </div>
        <.link
          :for={%{product: product, device_count: total} <- @entry.products}
          role="row"
          id={"product-#{product.id}"}
          navigate={~p"/org/#{@entry.org}/#{product}/insights"}
          class="grid grid-cols-[1fr_auto_auto] items-center gap-x-3 gap-y-2.5 border-b border-line-subtle px-4 py-3 transition-colors last:border-0 hover:bg-surface-muted md:flex md:gap-4"
        >
          <div role="cell" class="col-start-1 row-start-1 min-w-0 md:flex-1">
            <p class="truncate text-sm font-medium text-content-strong">{product.name}</p>
            <p class="text-xs text-content-muted">{deployment_groups_label(@fleet, product.id) || " "}</p>
          </div>
          <div role="cell" class="col-span-2 col-start-1 row-start-2 md:w-94">
            <.online_meter counts={product_online(@online, @entry.org.id, product.id)} total={total} />
          </div>
          <div role="cell" class="col-start-2 row-start-1 md:w-27.5">
            <.health_chip :if={total > 0} health={product_health(@fleet, product.id)} />
          </div>
          <span class="col-start-3 row-span-2 row-start-1 lucide-chevron-right size-4 text-content-faint" aria-hidden="true"></span>
        </.link>
      </div>
      <.link
        :if={@new_product_row && @entry.products != [] && authorized?(:"product:create", @entry.role)}
        navigate={~p"/org/#{@entry.org}/new"}
        class="flex h-11 items-center gap-2 border-t border-line-subtle px-4 text-sm font-medium text-content-body hover:bg-surface-muted hover:text-content-strong md:hidden"
      >
        <span class="lucide-plus size-4" aria-hidden="true"></span> New product
      </.link>
    </div>
    """
  end

  attr(:counts, :any, required: true, doc: "`{connected, disconnected}`, or nil while it loads")
  attr(:total, :integer, required: true)
  attr(:class, :any, default: "md:w-full md:max-w-45", doc: "the meter's width from md up; on a phone it fills the row")

  defp online_meter(%{total: 0} = assigns) do
    ~H"""
    <p class="text-sm text-content-muted">No devices yet</p>
    """
  end

  # On a phone the count sits in a fixed slot to the left of the meter, so
  # meters line up from row to row; from md up the meter goes under it.
  defp online_meter(assigns) do
    ~H"""
    <div class="flex items-center gap-3 md:block">
      <p class="min-w-36 shrink-0 text-sm whitespace-nowrap text-content-muted tabular-nums md:min-w-0">
        <span class="online-count font-medium text-content-strong">{delimited(@counts && elem(@counts, 0))}</span> of {delimited(@total)}<span class="md:hidden"> online</span>
      </p>
      <div class={["h-1 flex-1 overflow-hidden rounded-full bg-base-800 md:mt-1.5", @class]}>
        <div :if={@counts} class="h-full rounded-full bg-status-online" style={"width: #{online_percent(@counts)}%"}></div>
      </div>
    </div>
    """
  end

  attr(:health, :map, default: nil, doc: "the health counts, or nil while they load")

  defp health_chip(%{health: nil} = assigns) do
    ~H"""
    <span class="text-sm text-content-faint">—</span>
    """
  end

  defp health_chip(%{health: %{unhealthy: unhealthy}} = assigns) when unhealthy > 0 do
    ~H"""
    <.badge tone="alert" class="inline-flex items-center gap-1.5">
      <.status_dot class="size-1.5 bg-alert" />{@health.unhealthy} unhealthy
    </.badge>
    """
  end

  defp health_chip(%{health: %{warning: warning}} = assigns) when warning > 0 do
    ~H"""
    <.badge tone="warning" class="inline-flex items-center gap-1.5">
      <.status_dot class="size-1.5 bg-warning" />{count_noun(@health.warning, "warning", "warnings")}
    </.badge>
    """
  end

  defp health_chip(%{health: %{healthy: healthy}} = assigns) when healthy > 0 do
    ~H"""
    <.badge tone="success" class="inline-flex items-center gap-1.5">
      <.status_dot class="size-1.5 bg-success" />Healthy
    </.badge>
    """
  end

  defp health_chip(assigns) do
    ~H"""
    <span class="text-xs text-content-faint">Not reported</span>
    """
  end

  attr(:entry, :map, required: true)

  defp org_actions(assigns) do
    ~H"""
    <.button type="link" square navigate={~p"/org/#{@entry.org}/settings/users"} aria-label="Users" title="Users">
      <span class="lucide-users size-4" aria-hidden="true"></span>
    </.button>
    <.button type="link" square navigate={~p"/org/#{@entry.org}/settings/keys"} aria-label="Signing keys" title="Signing keys">
      <span class="lucide-key-round size-4" aria-hidden="true"></span>
    </.button>
    <.button type="link" square navigate={~p"/org/#{@entry.org}/settings"} aria-label="Settings" title="Settings">
      <span class="lucide-settings size-4" aria-hidden="true"></span>
    </.button>
    """
  end

  attr(:item, :map, required: true)
  attr(:single_org?, :boolean, required: true)

  # On a phone an attention row wraps its detail line instead of cutting it
  # off, and the approval's button goes under the text so the title keeps the
  # width. From md up each row is one line with the action at the end.
  defp attention_row(%{item: %{kind: :approval}} = assigns) do
    ~H"""
    <div class="attention-item flex items-start gap-3 p-4 md:items-center md:gap-4">
      <span class="flex size-8 shrink-0 items-center justify-center rounded bg-notice-soft text-notice-content">
        <span class="lucide-hourglass size-4" aria-hidden="true"></span>
      </span>
      <div class="flex min-w-0 flex-1 flex-col items-start gap-3 md:flex-row md:items-center md:gap-4">
        <div class="w-full min-w-0 md:w-auto md:flex-1">
          <p class="text-sm font-medium text-content-strong">
            <%= if version = release_version(@item.step) do %>
              Release <span class="font-mono">{version}</span> is waiting for approval
            <% else %>
              A release is waiting for approval
            <% end %>
          </p>
          <p class="text-xs text-content-muted md:truncate">
            {place(@item, @single_org?)} · {@item.step.deployment_release.deployment_group.name} · {DeploymentWorkflowStep.label(@item.step)}
          </p>
        </div>
        <.button
          type="link"
          style={if authorized?(:"deployment_group:update", @item.entry.role), do: "primary", else: "secondary"}
          size="sm"
          navigate={~p"/org/#{@item.entry.org}/#{@item.product}/deployment_groups/#{@item.step.deployment_release.deployment_group}"}
        >
          {if authorized?(:"deployment_group:update", @item.entry.role), do: "Review release", else: "View release"}
        </.button>
      </div>
    </div>
    """
  end

  defp attention_row(%{item: %{kind: :unhealthy}} = assigns) do
    ~H"""
    <div class="attention-item relative flex items-start gap-3 p-4 md:items-center md:gap-4">
      <span class="flex size-8 shrink-0 items-center justify-center rounded bg-alert-soft text-alert-content">
        <span class="lucide-activity size-4" aria-hidden="true"></span>
      </span>
      <div class="min-w-0 flex-1">
        <p class="text-sm font-medium text-content-strong">
          {if @item.count == 1, do: "1 device is unhealthy", else: "#{delimited(@item.count)} devices are unhealthy"}
        </p>
        <p class="text-xs text-content-muted md:truncate">{place(@item, @single_org?)}</p>
      </div>
      <.view_devices_link navigate={~p"/org/#{@item.entry.org}/#{@item.product}/devices?health_status=unhealthy"} />
    </div>
    """
  end

  defp attention_row(%{item: %{kind: :failing_updates}} = assigns) do
    ~H"""
    <div class="attention-item relative flex items-start gap-3 p-4 md:items-center md:gap-4">
      <span class="flex size-8 shrink-0 items-center justify-center rounded bg-warning-soft text-warning-content">
        <span class="lucide-circle-pause size-4" aria-hidden="true"></span>
      </span>
      <div class="min-w-0 flex-1">
        <p class="text-sm font-medium text-content-strong">
          {if @item.count == 1,
            do: "1 device stopped taking updates after repeated failures",
            else: "#{delimited(@item.count)} devices stopped taking updates after repeated failures"}
        </p>
        <p class="text-xs text-content-muted md:truncate">{place(@item, @single_org?)} · {resumes_in(@item.until)}</p>
      </div>
      <.view_devices_link navigate={~p"/org/#{@item.entry.org}/#{@item.product}/devices?updates=failed-updates"} />
    </div>
    """
  end

  attr(:navigate, :string, required: true)

  # Its ::after stretches over the whole row (the row is `relative`), so the
  # row is the tap target. On a phone only the chevron shows; the label stays
  # for screen readers.
  defp view_devices_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="flex h-8 shrink-0 items-center gap-1 text-sm font-medium text-content-body after:absolute after:inset-0 hover:text-content-strong md:h-auto"
    >
      <span class="sr-only md:not-sr-only">View devices</span>
      <span class="lucide-chevron-right size-4 text-content-faint md:text-current" aria-hidden="true"></span>
    </.link>
    """
  end
end
