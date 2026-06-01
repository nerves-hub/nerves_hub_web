defmodule NervesHubWeb.Live.Product.Settings do
  use NervesHubWeb, :live_view

  alias NervesHub.Extensions
  alias NervesHub.Products
  alias NervesHubWeb.DeviceSocket

  def mount(_params, _session, socket) do
    product = Products.load_shared_secret_auth(socket.assigns.current_scope.product)

    socket =
      socket
      |> assign(:page_title, "#{product.name} Settings")
      |> sidebar_tab(:settings)
      |> assign(:product, product)
      |> assign(:banner_url, Products.banner_url(product, true))
      |> assign(:selected_banner, selected_banner(product))
      |> assign(:custom_banner_url, custom_banner_url(product))
      |> assign(:shared_secrets, product.shared_secret_auths)
      |> assign(:shared_auth_enabled, DeviceSocket.shared_secrets_enabled?())
      |> assign(:form, to_form(Ecto.Changeset.change(product)))
      |> assign(:available_extensions, extensions())
      |> allow_upload(:banner,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 5_000_000,
        auto_upload: true,
        progress: &handle_progress/3
      )

    {:ok, socket}
  end

  defp selected_banner(%{banner_upload_key: nil}), do: nil

  defp selected_banner(%{banner_upload_key: "default/" <> name}) do
    if Enum.any?(Products.default_banners(), &(&1.key == name)), do: name
  end

  defp selected_banner(_), do: :custom

  defp custom_banner_url(%{banner_upload_key: nil}), do: nil
  defp custom_banner_url(%{banner_upload_key: "default/" <> _}), do: nil
  defp custom_banner_url(product), do: Products.banner_url(product, true)

  def handle_progress(:banner, entry, socket) do
    if entry.done? do
      authorized!(:"product:update", socket.assigns.current_scope)

      product = socket.assigns.product

      [filepath] =
        consume_uploaded_entries(socket, :banner, fn %{path: path}, entry ->
          ext = Path.extname(entry.client_name)
          dest = Path.join(System.tmp_dir(), "banner_#{product.id}#{ext}")
          File.cp!(path, dest)
          {:ok, dest}
        end)

      socket =
        try do
          case Products.update_product_banner(product, filepath) do
            {:ok, product} ->
              socket
              |> assign(:product, product)
              |> assign(:banner_url, Products.banner_url(product, true))
              |> assign(:selected_banner, :custom)
              |> assign(:custom_banner_url, custom_banner_url(product))
              |> put_flash(:info, "Banner image uploaded successfully.")

            {:error, _} ->
              put_flash(socket, :error, "Failed to upload banner image.")
          end
        after
          File.rm(filepath)
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("validate-banner", _params, socket), do: {:noreply, socket}

  def handle_event("select-banner", %{"banner" => ""}, socket) do
    authorized!(:"product:update", socket.assigns.current_scope)

    case Products.remove_product_banner(socket.assigns.product) do
      {:ok, product} ->
        socket
        |> assign(:product, product)
        |> assign(:banner_url, nil)
        |> assign(:selected_banner, nil)
        |> assign(:custom_banner_url, nil)
        |> put_flash(:info, "Banner removed.")
        |> noreply()

      {:error, _} ->
        socket
        |> put_flash(:error, "Failed to remove banner.")
        |> noreply()
    end
  end

  def handle_event("select-banner", %{"banner" => banner}, socket) do
    authorized!(:"product:update", socket.assigns.current_scope)

    case Products.set_default_banner(socket.assigns.product, banner) do
      {:ok, product} ->
        socket
        |> assign(:product, product)
        |> assign(:banner_url, Products.banner_url(product, true))
        |> assign(:selected_banner, banner)
        |> assign(:custom_banner_url, nil)
        |> put_flash(:info, "Banner updated.")
        |> noreply()

      {:error, _} ->
        socket
        |> put_flash(:error, "Failed to update banner.")
        |> noreply()
    end
  end

  def handle_event("add-shared-secret", _params, socket) do
    authorized!(:"product:update", socket.assigns.current_scope)

    {:ok, _} = Products.create_shared_secret_auth(socket.assigns.product)

    refreshed = Products.load_shared_secret_auth(socket.assigns.product)

    socket
    |> assign(:shared_secrets, refreshed.shared_secret_auths)
    |> push_event("sharedsecret:created", %{})
    |> put_flash(:info, "A new Shared Secret has been created.")
    |> noreply()
  end

  def handle_event("deactivate-shared-secret", %{"shared_secret_id" => shared_secret_id}, socket) do
    authorized!(:"product:update", socket.assigns.current_scope)

    product = socket.assigns.product

    {:ok, _} = Products.deactivate_shared_secret_auth(product, shared_secret_id)

    refreshed = Products.load_shared_secret_auth(product)

    socket
    |> assign(:shared_secrets, refreshed.shared_secret_auths)
    |> put_flash(:info, "The Shared Secret has been deactivated.")
    |> noreply()
  end

  def handle_event("delete-product", _params, socket) do
    authorized!(:"product:delete", socket.assigns.current_scope)

    case Products.delete_product(socket.assigns.product) do
      {:ok, _product} ->
        socket
        |> put_flash(:info, "Product deleted successfully.")
        |> push_navigate(to: ~p"/org/#{socket.assigns.current_scope.org}")
        |> noreply()

      {:error, _changeset} ->
        message =
          "There was an error deleting the Product. Please delete all Firmware and Devices first."

        socket
        |> put_flash(:error, message)
        |> put_flash(:error, message)
        |> noreply()
    end
  end

  def handle_event("update-extension", %{"extension" => extension} = params, socket) do
    value = params["value"]
    available = Extensions.list() |> Enum.map(&to_string/1)

    result =
      case {extension in available, value} do
        {true, "on"} ->
          Products.enable_extension_setting(socket.assigns.product, extension)

        {true, _} ->
          Products.disable_extension_setting(socket.assigns.product, extension)
      end

    socket =
      case result do
        {:ok, _pf} ->
          put_flash(
            socket,
            :info,
            "The #{extension} extension was #{(value == "on" && "enabled") || "disabled"} successfully."
          )

        {:error, _changeset} ->
          socket
          |> put_flash(
            :error,
            "Failed to update the #{extension} extension. Please contact support if this problem persists."
          )
      end

    {:noreply, socket}
  end

  defp extensions() do
    for extension <- Extensions.list(),
        into: %{},
        do: {extension, Extensions.module(extension).description()}
  end
end
