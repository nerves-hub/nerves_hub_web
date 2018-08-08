defmodule NervesHubWWWWeb.DashboardController do
  use NervesHubWWWWeb, :controller

  alias NervesHubCore.Products

  def index(%{assigns: %{tenant: tenant}} = conn, _params) do
    products = Products.list_products_by_tenant(tenant)
    conn
    |> render("index.html", products: products, conn: conn)
  end
end
