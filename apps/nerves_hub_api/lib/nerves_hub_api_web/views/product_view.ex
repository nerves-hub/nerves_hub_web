defmodule NervesHubAPIWeb.ProductView do
  use NervesHubAPIWeb, :view
  alias NervesHubAPIWeb.ProductView

  def render("index.json", %{products: products}) do
    %{data: render_many(products, ProductView, "product.json")}
  end

  def render("show.json", %{product: product}) do
    %{data: render_one(product, ProductView, "product.json")}
  end

  def render("product.json", %{product: product}) do
    %{
      name: product.name,
      delta_updatable: product.delta_updatable
    }
  end
end
