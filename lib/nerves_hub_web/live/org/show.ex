defmodule NervesHubWeb.Live.Org.Show do
  use NervesHubWeb, :live_view

  alias NervesHub.Products

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
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
