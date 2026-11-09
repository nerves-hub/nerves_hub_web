defmodule NervesHubWeb.Live.Org.Show do
  @moduledoc """
  An organization's Products tab, the page its name links to.

  Most organizations have one product, so the layout follows the count. One
  product gets a card of its own, with its figures and a link to each of its
  pages. Two to five get a card each, two to a row. Past that they're a table
  that can be filtered and sorted. An organization with none is offered a
  form to create its first.

  Above the products sits what needs someone's attention (releases waiting
  for approval, unhealthy devices, devices whose updates keep failing), the
  same as on the organizations page.

  Device totals load with the page, so products can be sorted by size before
  anything renders. Online counts, health, deployment groups and errors load
  afterwards.
  """
  use NervesHubWeb, :live_view

  import NervesHubWeb.Components.Fleet

  alias NervesHub.Accounts
  alias NervesHub.Devices
  alias NervesHub.ErrorReports
  alias NervesHub.Extensions
  alias NervesHub.Products
  alias NervesHub.Products.Product
  alias NervesHubWeb.Components.Fleet
  alias NervesHubWeb.Mounts.OrgCounts

  on_mount(OrgCounts)

  # The most products that get a card each. Past this they're a table.
  @card_limit 5

  @sorts [{"Most devices", "devices"}, {"Name", "name"}, {"Newest", "newest"}]

  @update_tool_labels %{"fwup" => "fwup", "esp-idf" => "ESP-IDF", "rauc" => "RAUC", "atomvm" => "AtomVM"}

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    products = load_products(scope)

    socket
    |> page_title("Products - #{scope.org.name}")
    |> sidebar_tab(:products)
    |> assign(:org, scope.org)
    |> assign(:entry, %{org: scope.org, role: scope.role, products: products})
    |> assign(:card_limit, @card_limit)
    |> assign(:online, %{})
    |> assign(:fleet, nil)
    |> assign(:attention, nil)
    |> assign(:errors, nil)
    |> assign(:filter, "")
    |> assign(:sort, "devices")
    |> assign(:sorts, @sorts)
    |> assign(:product_form, to_form(%{"name" => ""}, as: :product))
    |> load_figures(scope, products)
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_event("filter", params, socket) do
    sort = if params["sort"] in Enum.map(@sorts, &elem(&1, 1)), do: params["sort"], else: "devices"

    socket
    |> assign(:filter, String.trim(params["filter"] || ""))
    |> assign(:sort, sort)
    |> noreply()
  end

  # Only keeps the address preview in step with the name. Errors come from
  # saving, so typing clears them until the next try.
  def handle_event("validate_product", %{"product" => params}, socket) do
    socket
    |> assign(:product_form, to_form(params, as: :product))
    |> noreply()
  end

  # The organization's first product, from the form shown in place of the
  # products. Every device extension starts on, as on the New product page.
  def handle_event("create_product", %{"product" => params}, %{assigns: %{current_scope: scope}} = socket) do
    authorized!(:"product:create", scope)

    extensions = Map.new(Extensions.list(), &{Atom.to_string(&1), "true"})
    params = %{"name" => params["name"], "org_id" => scope.org.id, "extensions" => extensions}

    case Products.create_product(params) do
      {:ok, product} ->
        socket
        |> put_flash(:info, "Product created successfully.")
        |> push_navigate(to: ~p"/org/#{scope.org}/#{product}/devices")
        |> noreply()

      {:error, %Ecto.Changeset{} = changeset} ->
        socket
        |> assign(:product_form, to_form(changeset))
        |> noreply()
    end
  end

  @impl Phoenix.LiveView
  def handle_async(:online, {:ok, counts}, socket) do
    socket
    |> assign(:online, %{socket.assigns.org.id => counts})
    |> noreply()
  end

  def handle_async(:fleet, {:ok, fleet}, socket) do
    socket
    |> assign(:fleet, fleet)
    |> assign(:attention, attention_items([socket.assigns.entry], fleet))
    |> noreply()
  end

  def handle_async(:errors, {:ok, errors}, socket) do
    socket
    |> assign(:errors, errors)
    |> noreply()
  end

  # A figure that failed to load stays a dash rather than taking the page down.
  def handle_async(_name, {:exit, _reason}, socket), do: {:noreply, socket}

  # The products the user can see, each with its device total, largest first.
  # Ties keep the alphabetical order the query returns.
  defp load_products(scope) do
    products = scope |> Products.get_products() |> Enum.sort_by(& &1.name)
    device_counts = products |> Enum.map(& &1.id) |> Devices.count_by_product()

    products
    |> Enum.map(&%{product: &1, device_count: Map.get(device_counts, &1.id, 0)})
    |> Enum.sort_by(&(-&1.device_count))
  end

  defp load_figures(socket, _scope, []), do: socket

  defp load_figures(socket, scope, products) do
    product_ids = Enum.map(products, & &1.product.id)
    with_error_reports = for %{product: product} <- products, product.extensions.error_reports, do: product.id

    socket
    |> start_async(:online, fn -> Accounts.get_org_device_counts(scope, scope.org.id) end)
    |> start_async(:fleet, fn -> Fleet.load(product_ids) end)
    |> start_async(:errors, fn -> ErrorReports.unresolved_counts_by_product(with_error_reports) end)
  end

  defp visible_products(products, filter, sort) do
    filter = String.downcase(filter)

    products
    |> Enum.filter(&String.contains?(String.downcase(&1.product.name), filter))
    |> sort_products(sort)
  end

  defp sort_products(products, "name"), do: Enum.sort_by(products, &String.downcase(&1.product.name))
  defp sort_products(products, "newest"), do: Enum.sort_by(products, & &1.product.inserted_at, {:desc, NaiveDateTime})
  defp sort_products(products, _devices), do: products

  defp total_devices(entry), do: entry.products |> Enum.map(& &1.device_count) |> Enum.sum()

  defp update_tools(%Product{allowed_update_tools: tools}) do
    Enum.map_join(tools, ", ", &Map.get(@update_tool_labels, &1, &1))
  end

  defp created(%Product{inserted_at: inserted_at}), do: Calendar.strftime(inserted_at, "%B %Y")

  defp approvals_count(nil, _product_id), do: nil

  defp approvals_count(fleet, product_id) do
    Enum.count(fleet.approvals, &(&1.deployment_release.deployment_group.product_id == product_id))
  end

  # A product's unresolved errors: `:off` when it doesn't take error reports,
  # nil while the counts load.
  defp unresolved_errors(%Product{extensions: %{error_reports: true}} = product, errors) do
    errors && Map.get(errors, product.id, 0)
  end

  defp unresolved_errors(_product, _errors), do: :off

  defp errors_label(:off), do: "Error reports off"
  defp errors_label(nil), do: nil
  defp errors_label(0), do: "No unresolved errors"
  defp errors_label(count), do: count_noun(count, "unresolved error", "unresolved errors")

  defp approvals_label(nil), do: nil
  defp approvals_label(0), do: "None awaiting approval"
  defp approvals_label(count), do: "#{delimited(count)} awaiting approval"

  # Where a product card's footer links go, in the product sidebar's order.
  defp product_links(org, product, :full) do
    [
      {"Devices", ~p"/org/#{org}/#{product}/devices"},
      {"Deployment groups", ~p"/org/#{org}/#{product}/deployment_groups"},
      {"Firmware", ~p"/org/#{org}/#{product}/firmware"},
      {"Archives", ~p"/org/#{org}/#{product}/archives"},
      {"Support scripts", ~p"/org/#{org}/#{product}/scripts"},
      product.extensions.error_reports && {"Errors", ~p"/org/#{org}/#{product}/errors"},
      {"Notifications", ~p"/org/#{org}/#{product}/notifications"},
      {"Settings", ~p"/org/#{org}/#{product}/settings"}
    ]
    |> Enum.filter(& &1)
  end

  defp product_links(org, product, :short) do
    [
      {"Devices", ~p"/org/#{org}/#{product}/devices"},
      {"Deployment groups", ~p"/org/#{org}/#{product}/deployment_groups"},
      {"Firmware", ~p"/org/#{org}/#{product}/firmware"},
      product.extensions.error_reports && {"Errors", ~p"/org/#{org}/#{product}/errors"}
    ]
    |> Enum.filter(& &1)
  end

  ## Components

  attr(:label, :string, required: true)
  slot(:inner_block, required: true)
  slot(:detail, doc: "a line under the figure")

  defp stat(assigns) do
    ~H"""
    <div class="flex min-w-0 flex-col gap-1.5 bg-surface-raised p-4 md:px-6">
      <dt class="text-[11px]/4 font-medium tracking-wide text-content-faint uppercase">{@label}</dt>
      <dd class="flex min-h-8 items-center text-2xl font-medium text-content-strong tabular-nums">{render_slot(@inner_block)}</dd>
      <dd :if={@detail != []} class="text-xs text-content-muted">{render_slot(@detail)}</dd>
    </div>
    """
  end

  attr(:org, :map, required: true)
  attr(:product, :map, required: true)
  attr(:class, :any, default: nil)

  # What a product with no devices shows in place of its figures.
  defp no_devices(assigns) do
    ~H"""
    <div class={["flex flex-col items-start gap-3 border-t border-line-subtle p-4", @class]}>
      <div>
        <p class="text-sm font-medium text-content-strong">No devices yet</p>
        <p class="text-sm text-content-muted">Upload firmware, then connect a device with a shared secret or a certificate.</p>
      </div>
      <.link navigate={~p"/org/#{@org}/#{@product}/devices/new"} class="inline-flex items-center gap-1 text-sm font-medium text-primary hover:text-primary-hover">
        Connect your first device <span class="lucide-arrow-right size-4" aria-hidden="true"></span>
      </.link>
    </div>
    """
  end

  attr(:org, :map, required: true)
  attr(:product, :map, required: true)
  attr(:links, :list, required: true)

  # On a phone the links scroll sideways rather than wrap, so the footer
  # stays one row.
  defp product_footer(assigns) do
    ~H"""
    <nav
      aria-label={"#{@product.name} pages"}
      class="scrollbar-none flex h-12 items-center gap-5 overflow-x-auto border-t border-line-subtle bg-surface px-4 text-sm whitespace-nowrap md:px-6"
    >
      <span class="text-[11px]/4 font-medium tracking-wide text-content-faint uppercase">Go to</span>
      <.link :for={{label, path} <- @links} navigate={path} class="text-content-body hover:text-content-strong">{label}</.link>
    </nav>
    """
  end
end
