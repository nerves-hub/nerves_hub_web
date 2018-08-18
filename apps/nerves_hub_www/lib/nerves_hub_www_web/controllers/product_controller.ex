defmodule NervesHubWWWWeb.ProductController do
  use NervesHubWWWWeb, :controller

  alias NervesHubCore.Products
  alias NervesHubCore.Products.Product

  def index(%{assigns: %{org: org}} = conn, _params) do
    products = Products.list_products(org)
    render(conn, "index.html", products: products)
  end

  def new(conn, _params) do
    changeset = Products.change_product(%Product{})
    render(conn, "new.html", changeset: changeset, layout: false)
  end

  def create(%{assigns: %{org: org}} = conn, %{"product" => product_params}) do
    case Products.create_product(product_params |> Enum.into(%{"org_id" => org.id})) do
      {:ok, product} ->
        render_product_listing(conn)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_error(conn, "new.html", changeset: changeset, layout: false)
    end
  end

  def show(%{assigns: %{org: org}} = conn, %{"id" => id}) do
    {:ok, product} = Products.get_product_with_org(org, id)
    product = NervesHubCore.Repo.preload(product, :firmwares)
    render(conn, "show.html", product: product)
  end

  def edit(%{assigns: %{org: org}} = conn, %{"id" => id}) do
    {:ok, product} = Products.get_product_with_org(org, id)
    changeset = Products.change_product(product)
    render(conn, "edit.html", product: product, changeset: changeset, layout: false)
  end

  def update(%{assigns: %{org: org}} = conn, %{"id" => id, "product" => product_params}) do
    {:ok, product} = Products.get_product_with_org(org, id)

    case Products.update_product(
           product,
           product_params |> Enum.into(%{"org_id" => org.id})
         ) do
      {:ok, _product} ->
        render_product_listing(conn)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_error(conn, "edit.html", changeset: changeset, product: product)
    end
  end


  def delete(%{assigns: %{org: org}} = conn, %{"id" => id}) do
    {:ok, product} = Products.get_product_with_org(org, id)
    {:ok, _product} = Products.delete_product(product)

    render_product_listing(conn)
  end

  defp render_product_listing(%{assigns: %{org: org}} = conn) do    
    render_success(conn, "_listing.html",
                         products: Products.list_products(org))
  end

end
