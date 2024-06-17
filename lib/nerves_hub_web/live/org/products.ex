defmodule NervesHubWeb.Live.Org.Products do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Products

  def mount(_params, _session, socket) do
    products = Products.get_products_by_user_and_org(socket.assigns.user, socket.assigns.org)

    socket =
      socket
      |> assign(:page_title, "#{socket.assigns.org.name} / Products")
      |> assign(:products, products)

    {:ok, socket}
  end
end
