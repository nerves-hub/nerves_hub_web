defmodule NervesHubWeb.Live.Product.Settings do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Products
  alias NervesHubWeb.DeviceSocketSharedSecretAuth

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:shared_secrets, socket.assigns.product.shared_secret_auth)
      |> assign(:shared_auth_enabled, DeviceSocketSharedSecretAuth.enabled?())

    {:ok, socket}
  end

  def handle_event("delta-updated", %{"delta_updatable" => delta}, socket) do
    attrs = %{delta_updatable: delta == "true"}

    {:ok, product} = Products.update_product(socket.assigns.product, attrs)

    {:reply, assign(socket, :product, product)}
  end

  def handle_event("add-shared-secret", _params, socket) do
    {:ok, _} = Products.create_shared_secret_auth(socket.assigns.product)

    refreshed = Products.load_shared_secret_auth(socket.assigns.product)

    {:reply, assign(socket, :shared_secrets, refreshed.shared_secret_auth)}
  end

  def handle_event("copy-shared-secret", %{"value" => shared_secret_id}, socket) do
    auth =
      Enum.find(socket.assigns.product.shared_secret_auth, fn ssa ->
        ssa.id == String.to_integer(shared_secret_id)
      end)

    {:noreply, push_event(socket, "sharedsecret:clipcopy", %{secret: auth.secret})}
  end

  def handle_event("deactivate-shared-secret", %{"shared_secret_id" => shared_secret_id}, socket) do
    product = socket.assigns.product

    {:ok, _} = Products.deactivate_shared_secret_auth(product, shared_secret_id)

    refreshed = Products.load_shared_secret_auth(product)

    {:reply, assign(socket, :shared_secrets, refreshed.shared_secret_auth)}
  end
end
