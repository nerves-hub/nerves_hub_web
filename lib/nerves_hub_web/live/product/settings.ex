defmodule NervesHubWeb.Live.Product.Settings do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Products
  alias NervesHubWeb.DeviceSocket

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "#{socket.assigns.product.name} Settings")
      |> assign(:shared_secrets, socket.assigns.product.shared_secret_auths)
      |> assign(:shared_auth_enabled, DeviceSocket.shared_secrets_enabled?())

    {:ok, socket}
  end

  def handle_event("delta-updated", %{"delta_updatable" => delta}, socket) do
    authorized!(:update_product, socket.assigns.org_user)

    attrs = %{delta_updatable: delta == "true"}

    {:ok, product} = Products.update_product(socket.assigns.product, attrs)

    {:reply, assign(socket, :product, product)}
  end

  def handle_event("add-shared-secret", _params, socket) do
    authorized!(:update_product, socket.assigns.org_user)

    {:ok, _} = Products.create_shared_secret_auth(socket.assigns.product)

    refreshed = Products.load_shared_secret_auth(socket.assigns.product)

    {:reply, assign(socket, :shared_secrets, refreshed.shared_secret_auths)}
  end

  def handle_event("copy-shared-secret", %{"value" => shared_secret_id}, socket) do
    auth =
      Enum.find(socket.assigns.product.shared_secret_auths, fn ssa ->
        ssa.id == String.to_integer(shared_secret_id)
      end)

    {:noreply, push_event(socket, "sharedsecret:clipcopy", %{secret: auth.secret})}
  end

  def handle_event("deactivate-shared-secret", %{"shared_secret_id" => shared_secret_id}, socket) do
    authorized!(:update_product, socket.assigns.org_user)

    product = socket.assigns.product

    {:ok, _} = Products.deactivate_shared_secret_auth(product, shared_secret_id)

    refreshed = Products.load_shared_secret_auth(product)

    {:reply, assign(socket, :shared_secrets, refreshed.shared_secret_auths)}
  end

  def handle_event("delete-product", _parmas, socket) do
    authorized!(:delete_product, socket.assigns.org_user)

    with {:ok, _product} <- Products.delete_product(socket.assigns.product) do
      socket =
        socket
        |> put_flash(:info, "Product deleted successfully.")
        |> redirect(to: "/org/#{socket.assigns.org.name}")

      {:noreply, socket}
    end
  end
end
