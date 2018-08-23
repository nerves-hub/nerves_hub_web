defmodule NervesHubAPIWeb.ProductController do
  use NervesHubAPIWeb, :controller

  alias NervesHubCore.Products
  alias NervesHubCore.Products.Product

  action_fallback(NervesHubAPIWeb.FallbackController)

  def index(%{assigns: %{org: org}} = conn, _params) do
    products = Products.list_products(org)
    render(conn, "index.json", products: products)
  end

  def create(%{assigns: %{org: org}} = conn, params) do
    params =
      params
      |> Map.take(["name"])
      |> Map.put("org_id", org.id)

    with {:ok, product} <- Products.create_product(params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", product_path(conn, :show, org.name, product.name))
      |> render("show.json", product: product)
    end
  end

  def show(%{assigns: %{product: product}} = conn, _params) do
    render(conn, "show.json", product: product)
  end

  def delete(%{assigns: %{product: product}} = conn, _params) do
    with {:ok, %Product{}} <- Products.delete_product(product) do
      send_resp(conn, :no_content, "")
    end
  end

  def update(%{assigns: %{product: product}} = conn, %{"product" => params}) do
    with {:ok, product} <- Products.update_product(product, params) do
      render(conn, "show.json", product: product)
    end
  end
end
