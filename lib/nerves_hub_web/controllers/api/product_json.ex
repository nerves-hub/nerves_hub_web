defmodule NervesHubWeb.API.ProductJSON do
  @moduledoc false

  def index(%{products: products}) do
    %{data: for(product <- products, do: product(product))}
  end

  def show(%{product: product}) do
    %{data: product(product)}
  end

  def product(product) do
    %{
      name: product.name,
      delta_updatable: product.delta_updatable
    }
  end
end
