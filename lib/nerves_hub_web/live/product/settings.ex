defmodule NervesHubWeb.Live.Product.Settings do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Products
  alias NervesHubWeb.DeviceSocket

  def mount(_params, _session, socket) do
    product = Products.load_shared_secret_auth(socket.assigns.product)

    socket =
      socket
      |> assign(:page_title, "#{product.name} Settings")
      |> assign(:product, product)
      |> assign(:shared_secrets, product.shared_secret_auths)
      |> assign(:shared_auth_enabled, DeviceSocket.shared_secrets_enabled?())
      |> assign(:form, to_form(Ecto.Changeset.change(product)))
      |> assign(:show_shared_secret, nil)

    {:ok, socket}
  end

  def handle_event("update", %{"product" => params}, socket) do
    authorized!(:"product:update", socket.assigns.org_user)

    {:ok, product} = Products.update_product(socket.assigns.product, params)
    {:noreply, assign(socket, :product, product)}
  end

  def handle_event("add-shared-secret", _params, socket) do
    authorized!(:"product:update", socket.assigns.org_user)

    {:ok, _} = Products.create_shared_secret_auth(socket.assigns.product)

    refreshed = Products.load_shared_secret_auth(socket.assigns.product)

    socket
    |> assign(:shared_secrets, refreshed.shared_secret_auths)
    |> push_event("sharedsecret:created", %{})
    |> noreply()
  end

  def handle_event("show-secret", %{"auth" => auth_id}, socket) do
    socket
    |> assign(:show_shared_secret, auth_id)
    |> noreply()
  end

  def handle_event("deactivate-shared-secret", %{"shared_secret_id" => shared_secret_id}, socket) do
    authorized!(:"product:update", socket.assigns.org_user)

    product = socket.assigns.product

    {:ok, _} = Products.deactivate_shared_secret_auth(product, shared_secret_id)

    refreshed = Products.load_shared_secret_auth(product)

    {:noreply, assign(socket, :shared_secrets, refreshed.shared_secret_auths)}
  end

  def handle_event("delete-product", _parmas, socket) do
    authorized!(:"product:delete", socket.assigns.org_user)

    case Products.delete_product(socket.assigns.product) do
      {:ok, _product} ->
        socket =
          socket
          |> put_flash(:info, "Product deleted successfully.")
          |> push_navigate(to: ~p"/org/#{socket.assigns.org.name}")

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "There was an error deleting the Product. Please delete all Firmware and Devices first."
         )}
    end
  end
end
