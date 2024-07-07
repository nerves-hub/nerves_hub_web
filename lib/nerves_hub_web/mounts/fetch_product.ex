defmodule NervesHubWeb.Mounts.FetchProduct do
  import Phoenix.Component

  alias NervesHub.Products

  def on_mount(:default, %{"hashid" => hashid}, _session, socket) do
    socket =
      assign_new(socket, :product, fn ->
        {:ok, [product_id]} = decode(hashid)
        Products.get_product_by_user_and_id!(socket.assigns.user, product_id)
      end)

    {:cont, socket}
  end

  defp decode(product_hashid) do
    hashid = Application.get_env(:nerves_hub, :hashid_for_products)
    Hashids.decode(hashid, product_hashid)
  end
end
