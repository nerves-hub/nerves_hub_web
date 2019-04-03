defmodule NervesHubWWWWeb.ProductController do
  use NervesHubWWWWeb, :controller

  alias NervesHubWebCore.Products
  alias NervesHubWebCore.Products.Product

  plug(:validate_role, [org: :write] when action in [:new, :create])
  plug(:validate_role, [org: :read] when action in [:index])
  plug(:validate_role, [org: :delete] when action in [:delete])

  plug(:validate_role, [product: :write] when action in [:update])

  def index(%{assigns: %{user: user, current_org: org}} = conn, _params) do
    products = Products.get_products_by_user_and_org(user, org)
    render(conn, "index.html", products: products)
  end

  def new(conn, _params) do
    changeset = Products.change_product(%Product{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(%{assigns: %{user: user, current_org: org}} = conn, %{"product" => product_params}) do
    params = Enum.into(product_params, %{"org_id" => org.id})

    case Products.create_product(user, params) do
      {:ok, product} ->
        conn
        |> put_flash(:info, "Product created successfully.")
        |> redirect(to: product_path(conn, :show, product))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    product = Products.get_product!(id)

    conn
    |> assign(:product, product)
    |> validate_role(product: :read)
    |> render("show.html", product: product)
  end

  def edit(conn, %{"id" => id}) do
    product = Products.get_product!(id)
    changeset = Products.change_product(product)
    render(conn, "edit.html", product: product, changeset: changeset)
  end

  def update(%{assigns: %{current_org: org}} = conn, %{"id" => id, "product" => product_params}) do
    product = Products.get_product!(id)

    case Products.update_product(
           product,
           product_params |> Enum.into(%{"org_id" => org.id})
         ) do
      {:ok, product} ->
        conn
        |> put_flash(:info, "Product updated successfully.")
        |> redirect(to: product_path(conn, :show, product))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "edit.html", product: product, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    product = Products.get_product!(id)
    {:ok, _product} = Products.delete_product(product)

    conn
    |> put_flash(:info, "Product deleted successfully.")
    |> redirect(to: product_path(conn, :index))
  end
end
