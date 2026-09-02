defmodule NervesHubWeb.Live.Product.Settings do
  use NervesHubWeb, :live_view

  alias NervesHub.DeviceLink
  alias NervesHub.Extensions
  alias NervesHub.Firmwares.UpdateTool
  alias NervesHub.Products
  alias NervesHub.Products.Product

  # How each optional format is described to a human. The tool module knows the
  # format; naming it for a settings page is presentation, so it lives here.
  # fwup is not listed: it is always accepted and cannot be turned off.
  # `label` is a noun, so it reads as both a heading ("Accept ...") and a flash
  # message ("... are now accepted").
  @optional_tools %{
    "esp-idf" => %{
      label: "ESP-IDF application images",
      description: "Allow .bin images built by ESP-IDF to be uploaded to this product, alongside fwup archives.",
      unsigned_field: :allow_unsigned_esp_idf_firmware,
      unsigned_label: "Allow unsigned ESP-IDF images",
      unsigned_description:
        "Accept ESP-IDF images that carry no Secure Boot v2 signature block. An image that is signed is always verified against this organization's signing keys, whether or not this is set."
    },
    "rauc" => %{
      label: "RAUC bundles",
      description:
        "Allow .raucb bundles to be uploaded to this product, alongside fwup archives. Bundles must be in the verity format and signed by a certificate registered as an organization key."
      # No unsigned variant: RAUC will not build an unsigned bundle, so there is
      # nothing for a product to opt into.
    },
    "atomvm" => %{
      label: "AtomVM packbeam archives",
      description:
        "Allow .avm archives built by rebar3 atomvm packbeam to be uploaded to this product, alongside fwup archives.",
      unsigned_field: :allow_unsigned_atomvm_firmware,
      unsigned_label: "Allow unsigned AtomVM archives",
      unsigned_description:
        "Accept packbeam archives that carry no signature. Nothing in the AtomVM toolchain signs by default, so a product built without nh-avm needs this. An archive that is signed is always verified, whether or not this is set."
    }
  }

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
      |> assign(:optional_tools, optional_tools())

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

  # Adds or removes one format, rather than rewriting the list: a product may
  # accept several, and replacing the list would silently drop the others.
  #
  # Turning a format off leaves its other settings — `allow_unsigned_esp_idf_firmware`,
  # say — as they were. They have no effect while the format is refused, and
  # keeping them means turning it back on restores the setup the product had.
  def handle_event("update-allowed-update-tool", %{"tool" => tool} = params, socket) do
    authorized!(:"product:update", socket.assigns.current_scope)

    case Enum.find(socket.assigns.optional_tools, &(&1.name == tool)) do
      nil ->
        # A format this instance does not offer. The changeset would refuse it
        # too, but not with a message that would mean anything to the reader.
        {:noreply, socket}

      %{label: label} ->
        allow = params["value"] == "on"
        current = socket.assigns.product.allowed_update_tools
        tools = if allow, do: Enum.uniq(current ++ [tool]), else: current -- [tool]

        update_setting(socket, %{allowed_update_tools: tools}, fn ->
          "#{label} are now #{(allow && "accepted") || "refused"} for this product."
        end)
    end
  end

  def handle_event("update-allow-unsigned", %{"tool" => tool} = params, socket) do
    authorized!(:"product:update", socket.assigns.current_scope)

    case Enum.find(socket.assigns.optional_tools, &(&1.name == tool)) do
      nil ->
        {:noreply, socket}

      %{unsigned_field: field, label: label} ->
        allow = params["value"] == "on"

        update_setting(socket, %{field => allow}, fn ->
          "Unsigned #{label} are now #{(allow && "allowed") || "refused"} for this product."
        end)

      %{} ->
        # A format with no unsigned variant. RAUC is one: it will not build an
        # unsigned bundle, so there is nothing for a product to opt into and
        # `@optional_tools` gives it no `unsigned_field`.
        #
        # The template only renders a toggle for formats that have one, so this
        # is not reachable by clicking. It is reachable by anything that can
        # send the event, and matching only the formats that do carry the field
        # made that a `CaseClauseError` rather than a no-op.
        {:noreply, socket}
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

  # Only formats this instance has enabled, so a product cannot be set to accept
  # something `Product.validate_allowed_update_tools/1` would then refuse.
  defp optional_tools() do
    enabled = Map.keys(UpdateTool.all())

    @optional_tools
    |> Enum.filter(fn {name, _details} -> name in enabled end)
    |> Enum.sort_by(fn {name, _details} -> name end)
    |> Enum.map(fn {name, details} -> Map.put(details, :name, name) end)
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
