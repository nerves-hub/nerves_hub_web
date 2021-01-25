defmodule NervesHubWWWWeb.ProductController do
  use NervesHubWWWWeb, :controller

  alias NervesHubWebCore.Products
  alias NervesHubWebCore.Products.Product

  action_fallback(NervesHubWWWWeb.FallbackController)

  plug(:validate_role, [org: :write] when action in [:new, :create])
  plug(:validate_role, [org: :read] when action in [:index])
  plug(:validate_role, [org: :delete] when action in [:delete])

  plug(:validate_role, [product: :write] when action in [:update])
  plug(:validate_role, [product: :read] when action in [:show])

  def index(%{assigns: %{user: user, org: org}} = conn, _params) do
    products = Products.get_products_by_user_and_org(user, org)
    render(conn, "index.html", products: products)
  end

  def new(conn, _params) do
    changeset = Products.change_product(%Product{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(%{assigns: %{user: user, org: org}} = conn, %{"product" => product_params}) do
    params = Enum.into(product_params, %{"org_id" => org.id})

    case Products.create_product(user, params) do
      {:ok, product} ->
        conn
        |> put_flash(:info, "Product created successfully.")
        |> redirect(to: Routes.device_path(conn, :index, org.name, product.name))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end

  def show(%{assigns: %{product: product}} = conn, _params) do
    conn
    |> render("show.html", product: product)
  end

  def edit(%{assigns: %{product: product}} = conn, _params) do
    changeset = Products.change_product(product)
    render(conn, "edit.html", product: product, changeset: changeset)
  end

  def update(%{assigns: %{org: org, product: product}} = conn, %{"product" => product_params}) do
    case Products.update_product(
           product,
           product_params |> Enum.into(%{"org_id" => org.id})
         ) do
      {:ok, product} ->
        conn
        |> put_flash(:info, "Product updated successfully.")
        |> redirect(to: Routes.device_path(conn, :index, org.name, product.name))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "edit.html", product: product, changeset: changeset)
    end
  end

  def delete(%{assigns: %{org: org, product: product}} = conn, _params) do
    with {:ok, _product} <- Products.delete_product(product) do
      conn
      |> put_flash(:info, "Product deleted successfully.")
      |> redirect(to: Routes.product_path(conn, :index, org.name))
    end
  end

  def devices_export(%{assigns: %{product: product}} = conn, _params) do
    filename = "#{product.name}-devices.csv"
    send_download(conn, {:binary, Products.devices_csv(product)}, filename: filename)
  end
end
