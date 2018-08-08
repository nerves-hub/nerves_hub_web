defmodule NervesHubWWWWeb.DashboardController do
  use NervesHubWWWWeb, :controller

  alias NervesHubCore.Products

  def index(%{assigns: %{tenant: tenant}} = conn, _params) do
    products = Products.list_products(tenant)
    conn
    |> render("index.html", products: products, conn: conn)
  end
end
