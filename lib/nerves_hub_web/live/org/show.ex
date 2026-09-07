defmodule NervesHubWeb.Live.Org.Show do
  use NervesHubWeb, :live_view

  alias NervesHub.Products

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    products = Products.get_products(scope)

    socket
    |> page_title("Products - #{scope.org.name}")
    |> assign(:org, scope.org)
    |> assign(:products, products)
    |> assign(:product_device_info, %{})
    |> sidebar_tab(:products)
    |> then(fn socket ->
      Enum.reduce(products, socket, fn product, acc ->
        assign_async(acc, :"product_counts_#{product.id}", fn ->
          key = :"product_counts_#{product.id}"
          {:ok, %{key => Products.get_product_counts(scope, product.id)}}
        end)
      end)
    end)
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_async(_name, _result, socket), do: {:noreply, socket}

  def fade_in(selector) do
    JS.show(
      to: selector,
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
  end
end
