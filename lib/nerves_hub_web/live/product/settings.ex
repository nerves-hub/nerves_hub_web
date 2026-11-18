defmodule NervesHubWeb.Live.Product.Settings do
  use NervesHubWeb, :live_view

  import NervesHubWeb.Components.ProductSettings, only: [title: 1, tabs: 1]
  import NervesHubWeb.Components.Switch, only: [switch: 1]
  import Number.Delimit, only: [number_to_delimited: 2]

  alias NervesHub.DeviceLink
  alias NervesHub.Devices
  alias NervesHub.Devices.BulkActions
  alias NervesHub.Extensions
  alias NervesHub.Firmwares.UpdateTool
  alias NervesHub.Products
  alias NervesHub.Products.HealthProfiles
  alias NervesHub.Products.Product
  alias NervesHubWeb.Mounts.RequireEveryDevice

  on_mount(RequireEveryDevice)

  # How each optional format is described to a human. The tool module knows the
  # format; naming it for a settings page is presentation, so it lives here.
  # fwup is not listed: it is always accepted and cannot be turned off.
  # `label` is a noun, so it reads as both a heading ("ESP-IDF application
  # images") and a flash message ("... are now accepted").
  @optional_tools %{
    "esp-idf" => %{
      label: "ESP-IDF application images",
      extension: ".bin",
      noun: "images",
      unsigned_field: :allow_unsigned_esp_idf_firmware,
      unsigned_label: "Allow unsigned ESP-IDF images",
      unsigned_description:
        "An image with no Secure Boot v2 signature block is accepted. A signed image is always checked against this organization's signing keys."
    },
    "rauc" => %{
      label: "RAUC bundles",
      extension: ".raucb",
      # No unsigned variant: RAUC will not build an unsigned bundle, so there is
      # nothing for a product to opt into.
      note: "Verity bundles, signed by a certificate registered as an organization key."
    },
    "atomvm" => %{
      label: "AtomVM packbeam archives",
      extension: ".avm",
      noun: "archives",
      unsigned_field: :allow_unsigned_atomvm_firmware,
      unsigned_label: "Allow unsigned AtomVM archives",
      unsigned_description:
        "Nothing in the AtomVM toolchain signs by default, so an archive built without nh-avm needs this. A signed archive is always checked."
    }
  }

  @decorate requires_membership()
  def mount(_params, _session, socket) do
    product = Products.load_shared_secret_auth(socket.assigns.current_scope.product)

    socket
    |> assign(:page_title, "#{product.name} Settings")
    |> sidebar_tab(:settings)
    |> assign(:product, product)
    |> assign(:shared_secrets, sort_secrets(product.shared_secret_auths))
    |> assign(:shared_auth_enabled, DeviceLink.shared_secrets_enabled?())
    |> assign(:new_secret_id, nil)
    |> assign(:profile_count, HealthProfiles.count_for_product(product))
    |> assign(:extensions, extensions())
    |> assign(:optional_tools, optional_tools())
    |> assign(:confirm, nil)
    |> assign(:delete_name, "")
    |> assign(:managed_progress, nil)
    |> assign(:reenabling, MapSet.new())
    |> assign_counts()
    |> ok()
  end

  ## Device extensions

  # Turning one on reaches every device that has it on in its own setting, and
  # needs no asking. Turning one off takes it from all of them, so it asks first.
  @decorate requires_permission(:"product:update")
  def handle_event("update-extension", %{"extension" => extension} = params, socket) do
    case {known_extension(extension), params["value"]} do
      {nil, _value} ->
        noreply(socket)

      {extension, "on"} ->
        set_product_extension(socket, extension, true)

      {extension, _off} ->
        socket
        |> assign(:confirm, %{kind: :extension_off, extension: extension})
        |> noreply()
    end
  end

  @decorate requires_permission(:"product:update")
  def handle_event("confirm-extension-off", %{"extension" => extension}, socket) do
    case known_extension(extension) do
      nil -> noreply(socket)
      extension -> socket |> assign(:confirm, nil) |> set_product_extension(extension, false)
    end
  end

  @decorate requires_permission(:"device:update")
  def handle_event("prepare-reenable-extension", %{"extension" => extension}, socket) do
    case known_extension(extension) do
      nil ->
        noreply(socket)

      extension ->
        socket
        |> assign(:confirm, %{kind: :extension_reenable, extension: extension, count: turned_off(socket, extension)})
        |> noreply()
    end
  end

  # Sets the extension in every device's own setting. The page only offers
  # turning it back on, for devices that have it off in their own setting.
  #
  # One run per extension at a time: the page hides the link while one runs,
  # but the event can be sent regardless.
  @decorate requires_permission(:"device:update")
  def handle_event("set-extension-for-devices", %{"extension" => extension, "enabled" => enabled}, socket) do
    %{product: product, current_scope: %{user: user}, reenabling: running} = socket.assigns
    enabled = enabled == "true"
    socket = assign(socket, :confirm, nil)

    if MapSet.member?(running, extension) do
      noreply(socket)
    else
      socket
      |> update(:reenabling, &MapSet.put(&1, extension))
      |> start_async({:set_extension, extension, enabled}, fn ->
        BulkActions.set_extension_for_product(product, extension, enabled, user)
      end)
      |> noreply()
    end
  end

  ## Device-managed updates

  @decorate requires_permission(:"product:update")
  def handle_event("update-default-managed-updates-allowed", params, socket) do
    allow = params["value"] == "on"

    update_setting(socket, %{default_managed_updates_allowed: allow}, fn ->
      "New devices #{(allow && "may") || "may not"} choose their own update mode."
    end)
  end

  # The device page gates the same grant on this permission, so changing it for
  # every device at once asks for no less.
  @decorate requires_permission(:"device:toggle-updates")
  def handle_event("prepare-managed-updates", %{"enabled" => enabled}, socket) do
    enabled = enabled == "true"
    %{device_total: total, managed_count: allowed} = socket.assigns

    socket
    |> assign(:confirm, %{
      kind: :managed_updates,
      enabled: enabled,
      count: if(enabled, do: total - allowed, else: allowed)
    })
    |> noreply()
  end

  # One run at a time. The page disables the buttons while one runs, but the
  # event can be sent regardless, and an allow and a revoke running together
  # would leave devices in a mix of both.
  @decorate requires_permission(:"device:toggle-updates")
  def handle_event("set-managed-updates-allowed-for-devices", %{"enabled" => enabled}, socket) do
    %{product: product, current_scope: %{user: user}, managed_progress: running} = socket.assigns
    enabled = enabled == "true"
    page = self()
    socket = assign(socket, :confirm, nil)

    on_progress = fn done, total -> send(page, {:managed_updates_progress, done, total}) end

    if running do
      noreply(socket)
    else
      socket
      |> assign(:managed_progress, %{enabled: enabled, done: 0, total: nil})
      |> start_async({:set_managed_updates_allowed, enabled}, fn ->
        BulkActions.set_managed_updates_allowed_for_product(product, enabled, user, on_progress: on_progress)
      end)
      |> noreply()
    end
  end

  ## Firmware

  @decorate requires_permission(:"product:update")
  def handle_event("update-require-unique-firmware-version", params, socket) do
    require_unique = params["value"] == "on"

    case Products.update_product(socket.assigns.product, %{require_unique_firmware_version: require_unique}) do
      {:ok, product} ->
        socket
        |> assign(:product, product)
        |> put_flash(:info, "Unique firmware versions are now #{(require_unique && "required") || "not required"}.")
        |> noreply()

      {:error, _changeset} ->
        socket
        |> put_flash(
          :error,
          "Failed to update the unique firmware version setting. Please contact support if this problem persists."
        )
        |> noreply()
    end
  end

  # Adds or removes one format, rather than rewriting the list: a product may
  # accept several, and replacing the list would silently drop the others.
  #
  # Turning a format off leaves its other settings — `allow_unsigned_esp_idf_firmware`,
  # say — as they were. They have no effect while the format is refused, and
  # keeping them means turning it back on restores the setup the product had.
  @decorate requires_permission(:"product:update")
  def handle_event("update-allowed-update-tool", %{"tool" => tool} = params, socket) do
    case Enum.find(socket.assigns.optional_tools, &(&1.name == tool)) do
      nil ->
        # A format this instance does not offer. The changeset would refuse it
        # too, but not with a message that would mean anything to the reader.
        noreply(socket)

      %{label: label} ->
        allow = params["value"] == "on"
        current = socket.assigns.product.allowed_update_tools
        tools = if allow, do: Enum.uniq(current ++ [tool]), else: current -- [tool]

        update_setting(socket, %{allowed_update_tools: tools}, fn ->
          "#{label} are now #{(allow && "accepted") || "refused"} for this product."
        end)
    end
  end

  @decorate requires_permission(:"product:update")
  def handle_event("update-allow-unsigned", %{"tool" => tool} = params, socket) do
    case Enum.find(socket.assigns.optional_tools, &(&1.name == tool)) do
      nil ->
        noreply(socket)

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
        noreply(socket)
    end
  end

  ## Shared secrets

  # Creating one doesn't ask: it changes nothing until a device uses it, and it
  # can be deactivated straight away.
  @decorate requires_permission(:"product:update")
  def handle_event("add-shared-secret", _params, socket) do
    {:ok, auth} = Products.create_shared_secret_auth(socket.assigns.product)

    socket
    |> assign(:new_secret_id, auth.id)
    |> refresh_shared_secrets()
    |> put_flash(:info, "Created a shared secret. Copy it with the button next to its key.")
    |> noreply()
  end

  @decorate requires_permission(:"product:update")
  def handle_event("prepare-deactivate-secret", %{"shared_secret_id" => id}, socket) do
    case Enum.find(socket.assigns.shared_secrets, &(to_string(&1.id) == id and is_nil(&1.deactivated_at))) do
      nil -> noreply(socket)
      auth -> socket |> assign(:confirm, %{kind: :deactivate_secret, auth: auth}) |> noreply()
    end
  end

  @decorate requires_permission(:"product:update")
  def handle_event("deactivate-shared-secret", %{"shared_secret_id" => shared_secret_id}, socket) do
    {:ok, auth} = Products.deactivate_shared_secret_auth(socket.assigns.product, shared_secret_id)

    socket
    |> assign(:confirm, nil)
    |> refresh_shared_secrets()
    |> put_flash(:info, "Deactivated #{auth.key}.")
    |> noreply()
  end

  ## Deleting the product

  @decorate requires_permission(:"product:delete")
  def handle_event("prepare-delete", _params, socket) do
    socket
    |> assign_counts()
    |> assign(:delete_name, "")
    |> assign(:confirm, %{kind: :delete_product})
    |> noreply()
  end

  @decorate requires_permission(:"product:delete")
  def handle_event("validate-delete-name", %{"name" => name}, socket) do
    noreply(assign(socket, :delete_name, name))
  end

  # Refused while the product has devices, counted again here rather than
  # trusted from the page: one may have connected since it was drawn.
  @decorate requires_permission(:"product:delete")
  def handle_event("delete-product", %{"name" => name}, socket) do
    %{product: product, current_scope: %{org: org}} = socket.assigns
    devices = Devices.get_device_count_by_product_id(product.id)

    cond do
      name != product.name ->
        noreply(assign(socket, :delete_name, name))

      devices > 0 ->
        socket
        |> assign(:confirm, nil)
        |> assign_counts()
        |> put_flash(:error, "#{product.name} still has devices, so it can't be deleted.")
        |> noreply()

      true ->
        case Products.delete_product(product) do
          {:ok, _product} ->
            socket
            |> put_flash(:info, "Deleted #{product.name}.")
            |> push_navigate(to: ~p"/org/#{org}")
            |> noreply()

          {:error, _changeset} ->
            socket
            |> assign(:confirm, nil)
            |> put_flash(
              :error,
              "#{product.name} couldn't be deleted. Please contact support if this problem persists."
            )
            |> noreply()
        end
    end
  end

  @decorate requires_membership()
  def handle_event("cancel-confirm", _params, socket) do
    noreply(assign(socket, :confirm, nil))
  end

  def handle_info({:managed_updates_progress, done, total}, socket) do
    socket
    |> update(:managed_progress, fn
      nil -> nil
      progress -> %{progress | done: done, total: total}
    end)
    |> noreply()
  end

  def handle_async({:set_managed_updates_allowed, enabled}, {:ok, results}, socket) do
    socket
    |> assign(:managed_progress, nil)
    |> assign_counts()
    |> put_managed_updates_flash(results, enabled)
    |> put_failed_flash(results.error, enabled)
    |> noreply()
  end

  def handle_async({:set_extension, extension, enabled}, {:ok, {:ok, count}}, socket) do
    socket
    |> update(:reenabling, &MapSet.delete(&1, extension))
    |> assign_counts()
    |> put_flash(
      :info,
      "Turned #{extension_name(extension)} #{(enabled && "back on") || "off"} for #{devices(count)}."
    )
    |> noreply()
  end

  def handle_async({:set_extension, extension, _enabled}, {:ok, {:error, :unknown_extension}}, socket) do
    socket
    |> update(:reenabling, &MapSet.delete(&1, extension))
    |> put_flash(:error, "That extension isn't one this platform supports.")
    |> noreply()
  end

  def handle_async(name, {:exit, reason}, socket) do
    _ =
      Sentry.capture_message(
        "Live.Product.Settings.handle_async:#{inspect(name)} failed due to exit: #{inspect(reason)}",
        result: :none
      )

    socket
    |> clear_running(name)
    |> assign_counts()
    |> put_flash(:error, "Updating the devices failed. Please contact support if this problem persists.")
    |> noreply()
  end

  # Only the run that ended lets go of its guard; another may still be going.
  defp clear_running(socket, {:set_managed_updates_allowed, _enabled}), do: assign(socket, :managed_progress, nil)

  defp clear_running(socket, {:set_extension, extension, _enabled}),
    do: update(socket, :reenabling, &MapSet.delete(&1, extension))

  defp set_product_extension(socket, extension, enabled) do
    %{product: product} = socket.assigns
    name = extension_name(extension)

    result =
      if enabled,
        do: Products.enable_extension_setting(product, extension),
        else: Products.disable_extension_setting(product, extension)

    case result do
      {:ok, updated} ->
        socket
        |> assign(:product, %{product | extensions: updated.extensions})
        |> put_flash(:info, "Turned #{name} #{(enabled && "on") || "off"} for #{product.name}.")
        |> noreply()

      {:error, _changeset} ->
        socket
        |> put_flash(:error, "Failed to update the #{name} extension. Please contact support if this problem persists.")
        |> noreply()
    end
  end

  # "Every device" only when none failed; otherwise how many did change, beside
  # the error saying how many didn't.
  defp put_managed_updates_flash(socket, %{error: 0}, enabled) do
    name = socket.assigns.product.name

    message =
      if enabled,
        do: "Every device in #{name} can now choose its update mode.",
        else: "No device in #{name} can choose its update mode now."

    put_flash(socket, :info, message)
  end

  defp put_managed_updates_flash(socket, %{ok: 0}, _enabled), do: socket

  defp put_managed_updates_flash(socket, %{ok: ok}, enabled) do
    put_flash(
      socket,
      :info,
      "#{devices(ok)} #{if enabled, do: "can now", else: "can no longer"} choose #{if ok == 1, do: "its", else: "their"} update mode."
    )
  end

  defp put_failed_flash(socket, 0, _enabled), do: socket

  defp put_failed_flash(socket, count, enabled) do
    put_flash(
      socket,
      :error,
      "#{devices(count)} couldn't be changed. #{(enabled && "Allow") || "Revoke"} on all again to try them."
    )
  end

  defp refresh_shared_secrets(socket) do
    secrets = Products.load_shared_secret_auth(socket.assigns.product).shared_secret_auths
    assign(socket, :shared_secrets, sort_secrets(secrets))
  end

  # Active before deactivated, newest first, so one just created is on top.
  defp sort_secrets(secrets), do: Enum.sort_by(secrets, &{!is_nil(&1.deactivated_at), -&1.id})

  defp assign_counts(socket) do
    product = socket.assigns.product
    %{total: total, on: on} = Devices.extension_counts(product)

    socket
    |> assign(:device_total, total)
    |> assign(:extensions_on_devices, on)
    |> assign(:managed_count, Devices.managed_updates_allowed_count(product))
  end

  defp known_extension(extension) do
    Enum.find_value(Extensions.list(), fn key -> to_string(key) == extension && extension end)
  end

  defp turned_off(socket, extension) do
    socket.assigns.device_total - Map.get(socket.assigns.extensions_on_devices, extension, 0)
  end

  defp devices(count), do: "#{number_to_delimited(count, precision: 0)} #{if count == 1, do: "device", else: "devices"}"

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
        |> put_flash(:error, "Failed to update the setting. Please contact support if this problem persists.")
        |> noreply()
    end
  end

  # What each extension does, in a line, in the order the card lists them: the
  # ones a fleet usually runs first. An extension missing here still shows,
  # last, with its module's own description.
  @extension_copy [
    health: {"Health", "Metrics, firmware metadata and alarms, reported together."},
    metrics: {"Metrics", "The device's metrics on their own, without Health's metadata and alarms."},
    geo: {"Geo", "Location from GeoIP, or a source you set up on the device, for the map."},
    logging: {"Logging", "Stream device logs to the Logs tab."},
    error_reports: {"Error reports", "Crashes and exceptions, grouped on the Errors page."},
    local_shell: {"Local shell", "A shell on the device's OS, beside the IEx console."},
    alarms: {"Alarms", "Alarms sent as they're raised and cleared, not on Health's schedule."},
    network_identity: {"Network identity", "Identities the device holds on networks like NetBird or iroh."}
  ]

  defp extensions() do
    order = Keyword.keys(@extension_copy)

    Extensions.list()
    |> Enum.sort_by(&(Enum.find_index(order, fn key -> key == &1 end) || length(order)))
    |> Enum.map(fn extension ->
      key = to_string(extension)

      {name, description} =
        Keyword.get_lazy(@extension_copy, extension, fn ->
          {Extensions.display_name(key), String.trim(Extensions.module(extension).description())}
        end)

      %{key: key, name: name, description: description}
    end)
  end

  defp extension_name(key) do
    Enum.find_value(@extension_copy, Extensions.display_name(key), fn {extension, {name, _description}} ->
      to_string(extension) == key && name
    end)
  end

  # The extensions on for the product that some devices have turned off in
  # their own setting, with how many have.
  defp turned_off_on_devices(product, extensions, on_devices, total) do
    for extension <- extensions,
        product_extension_on?(product, extension.key),
        off = total - Map.get(on_devices, extension.key, 0),
        off > 0,
        do: {extension, off}
  end

  ## Template helpers

  defp product_extension_on?(%{extensions: nil}, _key), do: false

  defp product_extension_on?(product, key), do: Map.get(product.extensions, String.to_existing_atom(key)) == true

  # The switch is flipped in the browser before the dialog asks, so it's drawn
  # off while it asks. Without that, the server's render wouldn't change on
  # Cancel, and the switch would stay off with the extension still on.
  defp asking_to_turn_off?(%{kind: :extension_off, extension: key}, key), do: true
  defp asking_to_turn_off?(_confirm, _key), do: false

  defp extensions_on(product, extensions), do: Enum.count(extensions, &product_extension_on?(product, &1.key))

  defp accepts?(product, tool), do: Product.accepts_update_tool?(product, tool.name)

  defp card_class(),
    do: "flex w-full flex-col overflow-clip rounded-card border border-line-default bg-surface-raised shadow-card"

  defp delimited(count), do: number_to_delimited(count, precision: 0)

  attr(:title, :string, required: true)
  attr(:description, :string, default: nil)
  slot(:aside, doc: "a quiet note at the end of the row")
  slot(:action, doc: "a button at the end of the row; under the text on a phone")
  slot(:inner_block, doc: "the description, when it needs markup")

  defp card_header(assigns) do
    ~H"""
    <div class="flex items-start justify-between gap-6 px-4 py-3.5 max-sm:flex-col max-sm:items-stretch max-sm:gap-3">
      <div class="flex min-w-0 flex-col gap-0.5">
        <h2 class="text-sm/5 font-semibold text-content-strong">{@title}</h2>
        <p :if={@description || @inner_block != []} class="text-ui/4.5 text-content-muted">
          {@description}{render_slot(@inner_block)}
        </p>
      </div>
      <div :if={@aside != []} class="shrink-0 text-ui/5 text-content-muted max-sm:hidden">{render_slot(@aside)}</div>
      <div :if={@action != []} class="flex shrink-0 max-sm:*:w-full">{render_slot(@action)}</div>
    </div>
    """
  end

  attr(:confirm, :map, required: true)
  attr(:product, :map, required: true)
  attr(:delete_name, :string, required: true)
  attr(:device_total, :integer, required: true)
  attr(:extensions_on_devices, :map, required: true)

  defp confirm_dialog(%{confirm: %{kind: :extension_off, extension: extension}} = assigns) do
    assigns =
      assign(assigns, name: extension_name(extension), on: Map.get(assigns.extensions_on_devices, extension, 0))

    ~H"""
    <.dialog id="confirm-dialog" title={"Turn off #{@name} for every device?"}>
      <p>Devices in {@product.name} stop using it once they hear of the change. Each keeps its own setting, so turning it back on here restores it.</p>
      <ul class="flex flex-col gap-1.5 rounded bg-surface-muted px-3 py-2.5">
        <li class="flex gap-2"><span class="text-content-faint">•</span><span><span class="font-mono">{delimited(@on)}</span> {if @on == 1, do: "device has", else: "devices have"} it on now</span></li>
        <li class="flex gap-2"><span class="text-content-faint">•</span><span>Connected devices drop it straight away; the rest when they next connect</span></li>
      </ul>
      <:actions>
        <.button style="contrast" phx-click="confirm-extension-off" phx-value-extension={@confirm.extension}>Turn off {@name}</.button>
      </:actions>
    </.dialog>
    """
  end

  defp confirm_dialog(%{confirm: %{kind: :extension_reenable}} = assigns) do
    assigns = assign(assigns, :name, extension_name(assigns.confirm.extension))

    ~H"""
    <.dialog id="confirm-dialog" title={"Turn #{@name} back on for #{devices(@confirm.count)}?"}>
      <p>
        {if @confirm.count == 1, do: "This device has", else: "These devices have"} {@name} turned off in {if @confirm.count == 1, do: "its", else: "their"} own setting. This turns it on for them, the same as doing it one device at a time.
      </p>
      <:actions>
        <.button style="primary" phx-click="set-extension-for-devices" phx-value-extension={@confirm.extension} phx-value-enabled="true">
          Turn on for {devices(@confirm.count)}
        </.button>
      </:actions>
    </.dialog>
    """
  end

  defp confirm_dialog(%{confirm: %{kind: :managed_updates, enabled: true}} = assigns) do
    ~H"""
    <.dialog id="confirm-dialog" title="Let every device choose its update mode?">
      <p>A device that can choose may switch itself to device-managed. It then asks for its deployment group's firmware instead of being sent it.</p>
      <ul class="flex flex-col gap-1.5 rounded bg-surface-muted px-3 py-2.5">
        <li class="flex gap-2">
          <span class="text-content-faint">•</span><span><span class="font-mono">{delimited(@confirm.count)}</span> {if @confirm.count == 1, do: "device can't", else: "devices can't"} choose now</span>
        </li>
        <li class="flex gap-2"><span class="text-content-faint">•</span><span>It can take a few minutes to reach them all</span></li>
      </ul>
      <:actions>
        <.button style="primary" phx-click="set-managed-updates-allowed-for-devices" phx-value-enabled="true">Allow on all</.button>
      </:actions>
    </.dialog>
    """
  end

  defp confirm_dialog(%{confirm: %{kind: :managed_updates, enabled: false}} = assigns) do
    ~H"""
    <.dialog id="confirm-dialog" title="Stop every device choosing its update mode?">
      <p>A device that is already device-managed stays that way. It just can't switch again.</p>
      <ul class="flex flex-col gap-1.5 rounded bg-surface-muted px-3 py-2.5">
        <li class="flex gap-2">
          <span class="text-content-faint">•</span><span><span class="font-mono">{delimited(@confirm.count)}</span> {if @confirm.count == 1, do: "device can", else: "devices can"} choose now</span>
        </li>
        <li class="flex gap-2"><span class="text-content-faint">•</span><span>It can take a few minutes to reach them all</span></li>
      </ul>
      <:actions>
        <.button style="primary" phx-click="set-managed-updates-allowed-for-devices" phx-value-enabled="false">Revoke on all</.button>
      </:actions>
    </.dialog>
    """
  end

  defp confirm_dialog(%{confirm: %{kind: :deactivate_secret, auth: auth}} = assigns) do
    assigns = assign(assigns, :auth, auth)

    ~H"""
    <.dialog id="confirm-dialog" title="Deactivate this shared secret?">
      <p class="font-mono text-xs break-all text-content-strong">{@auth.key}</p>
      <p>Devices that sign in with it can't connect again until they're given another one. It stays in the list, marked deactivated.</p>
      <:actions>
        <.button style="danger-solid" phx-click="deactivate-shared-secret" phx-value-shared_secret_id={@auth.id}>Deactivate secret</.button>
      </:actions>
    </.dialog>
    """
  end

  defp confirm_dialog(%{confirm: %{kind: :delete_product}} = assigns) do
    ~H"""
    <.dialog id="confirm-dialog" title={"Delete #{@product.name}?"}>
      <%= if @device_total > 0 do %>
        <p class="rounded-card border border-alert/40 bg-alert-soft p-3 text-alert-content">
          It still has {devices(@device_total)}, so it can't be deleted.
        </p>
      <% else %>
        <p>Its firmware, archives, deployment groups, support scripts and settings go with it. This can't be undone.</p>
        <form id="delete-product-form" phx-change="validate-delete-name" phx-submit="delete-product" class="flex flex-col gap-1.5">
          <label for="delete-product-name" class="text-ui/4 text-content-body">
            Type <span class="font-mono font-medium text-content-strong">{@product.name}</span> to confirm
          </label>
          <input
            id="delete-product-name"
            name="name"
            type="text"
            value={@delete_name}
            autocomplete="off"
            spellcheck="false"
            phx-mounted={JS.focus()}
            class="h-9 w-full rounded border border-line-control border-b-line-strong bg-surface-raised px-3 font-mono text-sm text-content-strong focus:border-line-control focus:ring-0 focus:outline focus:-outline-offset-1 focus:outline-focus-ring max-sm:h-11 max-sm:text-base"
          />
        </form>
      <% end %>
      <:actions :if={@device_total == 0}>
        <.button style="danger-solid" type="submit" form="delete-product-form" disabled={@delete_name != @product.name}>
          Delete {@product.name}
        </.button>
      </:actions>
    </.dialog>
    """
  end

  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  slot(:inner_block, required: true)
  slot(:actions)

  # Cancel, Escape and a click outside all send `cancel-confirm`.
  defp dialog(assigns) do
    ~H"""
    <NervesHubWeb.CoreComponents.modal id={@id} show on_cancel={JS.push("cancel-confirm")}>
      <div class="flex max-w-lg flex-col gap-4">
        <h2 id={"#{@id}-title"} class="pr-8 text-section-title text-content-strong">{@title}</h2>
        <div id={"#{@id}-description"} class="flex flex-col gap-3 text-ui/5 text-content-body">
          {render_slot(@inner_block)}
        </div>
        <div class="flex justify-end gap-2 max-sm:flex-col-reverse max-sm:*:h-11 max-sm:*:w-full">
          <.button phx-click={JS.exec("data-cancel", to: "##{@id}")}>Cancel</.button>
          {render_slot(@actions)}
        </div>
      </div>
    </NervesHubWeb.CoreComponents.modal>
    """
  end
end
