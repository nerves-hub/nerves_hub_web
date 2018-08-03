defmodule NervesHubCore.Plugs.Product do
  import Plug.Conn

  alias NervesHubCore.Products

  def init(opts) do
    opts
  end

  def call(%{params: %{"product_id" => product_id}} = conn, _opts) do
    with {:ok, product} <- Products.get_product_with_tenant(conn.assigns.tenant, product_id) do
      conn
      |> assign(:product, product)
    else
      _ -> conn
    end
  end

  def call(%{params: %{"product_name" => product_name}} = conn, _opts) do
    with {:ok, product} <- Products.get_product_by_tenant_id_and_name(conn.assigns.tenant.id, product_name) do
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
