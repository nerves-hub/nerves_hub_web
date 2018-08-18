defmodule NervesHubAPIWeb.Plugs.Product do
  import Plug.Conn

  alias NervesHubCore.Products

  def init(opts) do
    opts
  end

  def call(%{params: %{"product_name" => product_name}} = conn, _opts) do
    case Products.get_product_by_org_id_and_name(conn.assigns.org.id, product_name) do
      {:ok, product} ->
        conn
        |> assign(:product, product)

      _ ->
        conn
        |> put_resp_header("content-type", "application/json")
        |> send_resp(403, Jason.encode!(%{status: "Invalid product: #{product_name}"}))
        |> halt()
    end
  end
end
