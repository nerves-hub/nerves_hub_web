defmodule NervesHubWeb.Live.Org.Show do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Products

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    products = Products.get_products_by_user_and_org(socket.assigns.user, socket.assigns.org)

    socket =
      socket
      |> page_title("Products - #{socket.assigns.org.name}")
      |> assign(:products, products)

    {:ok, socket}
  end

  def fade_in(selector) do
    JS.show(
      to: selector,
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
  end
end
