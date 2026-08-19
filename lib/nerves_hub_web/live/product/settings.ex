defmodule NervesHubWeb.Live.Product.Settings do
  use NervesHubWeb, :live_view

  alias NervesHub.DeviceLink
  alias NervesHub.Extensions
  alias NervesHub.Firmwares.UpdateTool
  alias NervesHub.Products
  alias NervesHub.Products.Product

  def mount(_params, _session, socket) do
    product = Products.load_shared_secret_auth(socket.assigns.current_scope.product)

    socket =
      socket
      |> assign(:page_title, "#{product.name} Settings")
      |> sidebar_tab(:settings)
      |> assign(:product, product)
      |> assign(:shared_secrets, product.shared_secret_auths)
      |> assign(:shared_auth_enabled, DeviceLink.shared_secrets_enabled?())
      |> assign(:form, to_form(Ecto.Changeset.change(product)))
      |> assign(:available_extensions, extensions())
      |> assign(:esp_idf_available, UpdateTool.esp_idf_enabled?())

    {:ok, socket}
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

  def handle_event("update-require-unique-firmware-version", params, socket) do
    authorized!(:"product:update", socket.assigns.current_scope)

    require_unique = params["value"] == "on"

    socket =
      case Products.update_product(socket.assigns.product, %{
             require_unique_firmware_version: require_unique
           }) do
        {:ok, product} ->
          socket
          |> assign(:product, product)
          |> put_flash(
            :info,
            "Unique firmware versions are now #{(require_unique && "required") || "not required"}."
          )

        {:error, _changeset} ->
          put_flash(
            socket,
            :error,
            "Failed to update the unique firmware version setting. Please contact support if this problem persists."
          )
      end

    {:noreply, socket}
  end

  # Turning ESP-IDF off leaves `allow_unsigned_esp_idf_firmware` as it was. It
  # has no effect while the format is refused, and keeping it means turning the
  # format back on restores the setup the product had before.
  def handle_event("update-allow-esp-idf-firmware", params, socket) do
    authorized!(:"product:update", socket.assigns.current_scope)

    allow = params["value"] == "on"
    tools = if allow, do: ["fwup", "esp-idf"], else: ["fwup"]

    update_setting(socket, %{allowed_update_tools: tools}, fn ->
      "ESP-IDF application images are now #{(allow && "accepted") || "refused"} for this product."
    end)
  end

  def handle_event("update-allow-unsigned-esp-idf-firmware", params, socket) do
    authorized!(:"product:update", socket.assigns.current_scope)

    allow = params["value"] == "on"

    update_setting(socket, %{allow_unsigned_esp_idf_firmware: allow}, fn ->
      "Unsigned ESP-IDF images are now #{(allow && "allowed") || "refused"} for this product."
    end)
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

  defp update_setting(socket, attrs, message) do
    case Products.update_product(socket.assigns.product, attrs) do
      {:ok, product} ->
        socket
        |> assign(:product, product)
        |> put_flash(:info, message.())
        |> noreply()

      {:error, _changeset} ->
        socket
        |> put_flash(
          :error,
          "Failed to update the setting. Please contact support if this problem persists."
        )
        |> noreply()
    end
  end

  defp extensions() do
    for extension <- Extensions.list(),
        into: %{},
        do: {extension, Extensions.module(extension).description()}
  end
end
