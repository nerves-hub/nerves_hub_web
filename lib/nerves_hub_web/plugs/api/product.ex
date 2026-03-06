defmodule NervesHubWeb.API.Plugs.Product do
  import Plug.Conn

  alias NervesHub.Products

  def init(opts) do
    opts
  end

  def call(%{params: %{"product_name" => product_name}} = conn, _opts) do
    product = Products.get_product_by_name!(conn.assigns.current_scope, product_name)

    assign(conn, :product, product)
  end
end
