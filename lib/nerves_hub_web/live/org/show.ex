defmodule NervesHubWeb.Live.Org.Show do
  use NervesHubWeb, :live_view

  alias NervesHub.Devices.Connections
  alias NervesHub.Products

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    products = Products.get_products(scope)

    if connected?(socket), do: send(self(), :load_extras)

    socket
    |> page_title("Products - #{scope.org.name}")
    |> assign(:org, scope.org)
    |> assign(:products, products)
    |> assign(:product_device_info, %{})
    |> sidebar_tab(:products)
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_info(:load_extras, socket) do
    statuses =
      socket.assigns.products
      |> Enum.map(& &1.id)
      |> Connections.get_connection_status_by_products()

    {:noreply, assign(socket, :product_device_info, statuses)}
  end

  def fade_in(selector) do
    JS.show(
      to: selector,
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
  end
end
