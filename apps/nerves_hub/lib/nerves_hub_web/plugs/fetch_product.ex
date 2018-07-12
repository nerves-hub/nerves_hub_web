defmodule NervesHubWeb.Plugs.FetchProduct do
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
end
