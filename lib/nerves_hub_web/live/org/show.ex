defmodule NervesHubWeb.Live.Org.Show do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Devices.Connections
  alias NervesHub.Products

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    products = Products.get_products_by_user_and_org(socket.assigns.user, socket.assigns.org)

    socket =
      socket
      |> page_title("Products - #{socket.assigns.org.name}")
      |> assign(:products, products)
      |> assign(:banner_urls, banner_urls(products))
      |> assign(:product_device_info, %{})
      |> sidebar_tab(:products)

    if connected?(socket), do: send(self(), :load_extras)

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_info(:load_extras, socket) do
    statuses =
      Connections.get_connection_status_by_products(Enum.map(socket.assigns.products, & &1.id))

    {:noreply, assign(socket, :product_device_info, statuses)}
  end

  defp banner_urls(products) do
    for product <- products,
        url = Products.banner_url(product),
        into: %{} do
      {product.id, url}
    end
  end

  def fade_in(selector) do
    JS.show(
      to: selector,
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
  end
end
