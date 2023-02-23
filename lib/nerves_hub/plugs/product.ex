defmodule NervesHub.Plugs.Product do
  import Plug.Conn

  alias NervesHub.Products

  def init(opts) do
    opts
  end

  def call(%{params: %{"product_name" => product_name}} = conn, _opts) do
    with {:ok, product} <-
           Products.get_product_by_org_id_and_name(conn.assigns.org.id, product_name) do
      conn
      |> assign(:product, product)
    else
      _ -> conn
    end
  end

  def call(conn, _opts) do
    conn
  end
end
