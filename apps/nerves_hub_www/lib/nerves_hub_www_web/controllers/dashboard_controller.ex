defmodule NervesHubWWWWeb.DashboardController do
  use NervesHubWWWWeb, :controller

  alias NervesHubCore.Products

  def index(%{assigns: %{org: org}} = conn, _params) do
    products = Products.list_products(org)

    conn
    |> render("index.html", conn: conn, products: products)
  end
end
