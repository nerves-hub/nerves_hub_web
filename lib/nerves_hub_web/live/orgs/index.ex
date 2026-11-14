defmodule NervesHubWeb.Live.Orgs.Index do
  @moduledoc """
  The home page everyone lands on after signing in.

  Most people belong to one organization, so with one the page is that
  organization: its name heads the page and its products follow. With more,
  each gets a section of its own, largest first. From five up the user stars
  the ones they want in full, and only those get a section; until they star
  one, the four largest do. The rest share a compact table.

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

  import NervesHubWeb.Components.Fleet

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Scope
  alias NervesHub.Accounts.Starring
  alias NervesHub.Devices
  alias NervesHub.Devices.Pinning
  alias NervesHub.Devices.PubSub
  alias NervesHub.Tracker
  alias NervesHubWeb.Components.Fleet
  alias Phoenix.Socket.Broadcast

  @pinned_devices_limit 5

  # The most organizations that get a full section without the user choosing.
  # Past this, the user stars the ones they want in full and the rest are
  # listed in one table, so a member of many organizations doesn't scroll past
  # every product they belong to.
  @full_sections 4

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

  # Only an organization on the page can be starred, which is one the user
  # belongs to.
  def handle_event("toggle-star", %{"org_id" => org_id}, %{assigns: %{orgs: orgs}} = socket) do
    case Enum.find(orgs, &(to_string(&1.org.id) == org_id)) do
      nil -> {:noreply, socket}
      %{org: org} -> toggle_star(socket, org)
    end
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

    # Health, updates, deployment groups and approvals are figures over all of
    # a product's devices, so products in an org where the user's role is
    # limited to tagged devices are left out of them.
    product_ids =
      for entry <- orgs,
          not Scope.devices_limited?(Scope.put_role(scope, entry.role)),
          %{product: product} <- entry.products,
          do: product.id

    pinned_devices = Pinning.get_pinned_devices(scope)

    statuses =
      Map.new(pinned_devices, fn device ->
        {device.identifier, Tracker.connection_status(device)}
      end)

    socket
    |> assign(:page_title, "Organizations")
    |> assign(:onboarding, false)
    |> assign(:orgs, orgs)
    |> assign(:starred, Starring.starred_org_ids(scope))
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
    |> start_async(:fleet, fn -> Fleet.load(product_ids) end)
  end

  # Each organization with the user's role in it, its products and their
  # device totals, largest first. Ties keep the alphabetical order the query
  # returns.
  defp load_orgs(scope) do
    orgs_with_roles = Accounts.get_orgs_with_roles(scope)
    product_ids = for {org, _role} <- orgs_with_roles, product <- org.products, do: product.id
    device_counts = Devices.count_by_product(product_ids, scope.user)
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

  defp toggle_star(%{assigns: %{current_scope: scope, starred: starred}} = socket, org) do
    if MapSet.member?(starred, org.id) do
      {_, nil} = Starring.unstar_org(scope.user.id, org.id)

      socket
      |> assign(:starred, MapSet.delete(starred, org.id))
      |> noreply()
    else
      case Starring.star_org(scope.user.id, org.id) do
        :ok ->
          socket
          |> assign(:starred, MapSet.put(starred, org.id))
          |> noreply()

        {:error, _changeset} ->
          socket
          |> put_flash(:error, "#{org.name} couldn’t be starred. Please try again.")
          |> noreply()
      end
    end
  end

  # Whether the user picks which organizations get a section, by starring
  # them. With fewer, every organization gets one.
  defp stars_offered?(orgs), do: length(orgs) > @full_sections

  defp starred?(starred, entry), do: MapSet.member?(starred, entry.org.id)

  # Whether the user has starred any of their organizations, so the starred
  # ones are the ones with sections.
  defp stars_chosen?(orgs, starred), do: stars_offered?(orgs) and Enum.any?(orgs, &starred?(starred, &1))

  # The organizations that get a section of their own, and the rest. Both
  # keep the largest-first order.
  defp split_sections(orgs, starred) do
    cond do
      not stars_offered?(orgs) -> {orgs, []}
      stars_chosen?(orgs, starred) -> Enum.split_with(orgs, &starred?(starred, &1))
      true -> Enum.split(orgs, @full_sections)
    end
  end

  # Whether the strip of starred organizations has room for the slot that
  # asks for another star.
  defp room_for_star?(starred_entries), do: length(starred_entries) < @full_sections

  # The slot fills the rest of its row: two tiles to a row on a phone, four
  # from lg up.
  defp star_slot_span(1), do: "lg:col-span-3"
  defp star_slot_span(2), do: "col-span-2"
  defp star_slot_span(_count), do: nil

  defp attention_count(nil, _org_id), do: 0
  defp attention_count(attention, org_id), do: Enum.count(attention, &(&1.entry.org.id == org_id))

  defp pinned_place(device, single_org?) do
    if single_org?, do: device.product.name, else: "#{device.org.name} / #{device.product.name}"
  end

  defp offline_for(%{latest_connection: %{disconnected_at: %DateTime{} = at}}) do
    "Offline " <> duration(DateTime.diff(DateTime.utc_now(), at))
  end

  defp offline_for(_device), do: "Offline"

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

  attr(:entry, :map, required: true)
  attr(:starred, :boolean, required: true)

  # The star takes the 16px the design gives it, and the negative margin
  # widens what can be clicked to 24px without moving anything around it. It
  # sits above a row's stretched link, so clicking it doesn't open the
  # organization.
  defp star_toggle(assigns) do
    ~H"""
    <button
      type="button"
      id={"star-org-#{@entry.org.id}"}
      phx-click="toggle-star"
      phx-value-org_id={@entry.org.id}
      aria-pressed={to_string(@starred)}
      aria-label={"Star #{@entry.org.name}"}
      title={if @starred, do: "Unstar", else: "Star"}
      class="group/star relative z-10 -m-1 flex size-6 shrink-0 items-center justify-center rounded hover:cursor-pointer"
    >
      <span
        class={[
          "size-4",
          @starred && "lucide-star--fill text-warning group-hover/star:text-warning-content",
          !@starred && "lucide-star text-content-faint group-hover/star:text-content-strong"
        ]}
        aria-hidden="true"
      ></span>
    </button>
    """
  end
end
