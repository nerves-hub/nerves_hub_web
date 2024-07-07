defmodule NervesHubWeb.Plugs.Product do
  use NervesHubWeb, :plug

  alias NervesHub.Products

  def init(opts) do
    opts
  end

  def call(%{params: %{"hashid" => hashid}} = conn, _opts) do
    {:ok, [product_id]} = decode(hashid)

    product = Products.get_product_by_user_and_id!(conn.assigns.user, product_id)

    assign(conn, :product, product)
  end

  defp decode(product_hashid) do
    hashid = Application.get_env(:nerves_hub, :hashid_for_products)
    Hashids.decode(hashid, product_hashid)
  end
end
