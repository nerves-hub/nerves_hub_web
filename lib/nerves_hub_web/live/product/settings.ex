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
      |> assign(:form, to_form(Ecto.Changeset.change(socket.assigns.product)))

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

    {:noreply, assign(socket, :shared_secrets, refreshed.shared_secret_auths)}
  end

  def handle_event("copy-shared-secret", %{"value" => shared_secret_id}, socket) do
    auth =
      Enum.find(socket.assigns.product.shared_secret_auths, fn ssa ->
        ssa.id == String.to_integer(shared_secret_id)
      end)

    {:noreply, push_event(socket, "sharedsecret:clipcopy", %{secret: auth.secret})}
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

    with {:ok, _product} <- Products.delete_product(socket.assigns.product) do
      socket =
        socket
        |> put_flash(:info, "Product deleted successfully.")
        |> push_navigate(to: ~p"/org/#{socket.assigns.org.name}")

      {:noreply, socket}
    else
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
