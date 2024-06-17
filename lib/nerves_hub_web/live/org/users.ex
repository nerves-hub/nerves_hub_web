defmodule NervesHubWeb.Live.Org.Users do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Products

  def mount(_params, _session, socket) do
    products = Products.get_products_by_user_and_org(socket.assigns.user, socket.assigns.org)

    {:ok, assign(socket, :products, products)}
  end
end
