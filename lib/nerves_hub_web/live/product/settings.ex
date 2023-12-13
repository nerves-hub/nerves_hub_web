defmodule NervesHubWeb.Live.Product.Settings do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Products
  alias NervesHubWeb.DeviceSocketSharedSecretAuth

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:shared_auth_enabled, DeviceSocketSharedSecretAuth.enabled?())

    {:ok, socket}
  end

  def handle_event("delta-updated", %{"delta_updatable" => delta}, socket) do
    attrs = %{delta_updatable: delta == "true"}

    {:ok, product} = Products.update_product(socket.assigns.product, attrs)

    {:noreply, assign(socket, :product, product)}
  end

  def handle_event("add-shared-secret", _params, socket) do
    {:ok, _} = NervesHub.Products.create_shared_secret_auth(socket.assigns.product)

    {:ok, product} = Products.load_shared_secret_auth(socket.assigns.product)

    {:noreply, assign(socket, :product, product)}
  end
end
