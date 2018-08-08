defmodule NervesHubWWWWeb.ProductController do
  use NervesHubWWWWeb, :controller

  alias NervesHubCore.Products
  alias NervesHubCore.Products.Product

  def index(%{assigns: %{tenant: tenant}} = conn, _params) do
    products = Products.list_products(tenant)
    render(conn, "index.html", products: products)
  end

  def new(conn, _params) do
    changeset = Products.change_product(%Product{})
    render(conn, "new.html", changeset: changeset, layout: false)
  end

  def create(%{assigns: %{tenant: tenant}} = conn, %{"product" => product_params}) do
    case Products.create_product(product_params |> Enum.into(%{"tenant_id" => tenant.id})) do
      {:ok, _product} ->
        render_product_listing(conn)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_error(conn, "new.html", changeset: changeset, layout: false)
    end
  end

  def show(conn, %{"id" => id}) do
    product = Products.get_product!(id)
    render(conn, "show.html", product: product)
  end

  def edit(conn, %{"id" => id}) do
    product = Products.get_product!(id)
    changeset = Products.change_product(product)
    render(conn, "edit.html", product: product, changeset: changeset, layout: false)
  end

  def update(%{assigns: %{tenant: tenant}} = conn, %{"id" => id, "product" => product_params}) do
    product = Products.get_product!(id)

    case Products.update_product(
           product,
           product_params |> Enum.into(%{"tenant_id" => tenant.id})
         ) do
      {:ok, _product} ->
        render_product_listing(conn)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_error(conn, "edit.html", changeset: changeset, product: product)
    end
  end


  def delete(%{assigns: %{tenant: tenant}} = conn, %{"id" => id}) do
    {:ok, product} = Products.get_product_with_tenant(tenant, id)
    {:ok, _product} = Products.delete_product(product)

    render_product_listing(conn)
  end

  defp render_product_listing(%{assigns: %{tenant: tenant}} = conn) do    
    render_success(conn, "_listing.html",
                         products: Products.list_products(tenant))
  end

end
