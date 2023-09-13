defmodule NervesHubWeb.API.ProductController do
  use NervesHubWeb, :api_controller

  alias NervesHub.Products
  alias NervesHub.Products.Product

  action_fallback(NervesHubWeb.API.FallbackController)

  plug(:validate_role, [org: :read] when action in [:show])
  plug(:validate_role, [org: :write] when action in [:create])
  plug(:validate_role, [org: :delete] when action in [:delete])
  plug(:validate_role, [org: :admin] when action in [:update])

  def index(%{assigns: %{user: user, org: org}} = conn, _params) do
    products = Products.get_products_by_user_and_org(user, org)
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
      |> put_resp_header("location", Routes.api_product_path(conn, :show, org.name, product.name))
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
