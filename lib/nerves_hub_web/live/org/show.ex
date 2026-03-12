defmodule NervesHubWeb.Live.Org.Show do
  use NervesHubWeb, :live_view

  alias NervesHub.Products

  @impl Phoenix.LiveView
  @decorate requires_permission(:"organization:view")
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    products = Products.get_products(scope, with_counts: true)

    socket
    |> page_title("Products - #{scope.org.name}")
    |> assign(:org, scope.org)
    |> assign(:products, products)
    |> assign(:product_device_info, %{})
    |> sidebar_tab(:products)
    |> ok()
  end

  def fade_in(selector) do
    JS.show(
      to: selector,
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
  end
end
