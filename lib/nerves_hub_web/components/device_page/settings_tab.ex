defmodule NervesHubWeb.Components.DevicePage.SettingsTab do
  use NervesHubWeb, tab_component: :settings

  alias NervesHub.Certificate
  alias NervesHub.DeviceLink
  alias NervesHub.Devices
  alias NervesHub.Devices.CACertificates
  alias NervesHub.Devices.Certificates
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.Updates
  alias NervesHub.Extensions
  alias NervesHubWeb.Components.CAHelpers
  alias NervesHubWeb.Components.DateTimes
  alias NervesHubWeb.Components.Utils
  alias NervesHubWeb.CoreComponents

  def tab_params(_params, _uri, socket) do
    changeset = Ecto.Changeset.change(socket.assigns.device)

    socket
    |> assign(:settings_form, to_form(changeset))
    |> assign(:available_tags, Devices.distinct_tags_for_product(socket.assigns.current_scope.product))
    |> assign(:shared_secrets_enabled, DeviceLink.shared_secrets_enabled?())
    |> assign(:shared_secrets, Devices.list_shared_secret_auths(socket.assigns.device))
    |> assign(:new_shared_secret, nil)
    |> allow_upload(:certificate,
      accept: :any,
      auto_upload: true,
      max_entries: 1,
      progress: &handle_progress/3
    )
    |> cont()
  end

  # Leaving the tab drops the key list, and a new secret not yet dismissed.
  def cleanup(), do: [:shared_secrets, :new_shared_secret]

  def render(assigns) do
    device = Certificates.preload_device_certificates(assigns.device, force: true)

    # A device certificate names its signer by key id (its AKI, the CA's SKI)
    # rather than by a foreign key, and the signer may never have been
    # registered - so the lookup can come up empty.
    signer_cas = CACertificates.by_ski(device.org_id, Enum.map(device.device_certificates, & &1.aki))

    assigns =
      assigns
      |> Map.put(:device, device)
      |> Map.put(:signer_cas, signer_cas)

    ~H"""
    <div
      id="settings-tab"
      phx-mounted={JS.remove_class("opacity-0")}
      class="tab-content flex flex-col items-start justify-between gap-4 p-6 opacity-0 transition-all duration-500 phx-click-loading:opacity-50"
    >
      <.form id="settings-form" for={@settings_form} class="w-full" phx-change="validate-device-settings" phx-submit="update-device-settings">
        <div class="flex w-full flex-col rounded-md border border-line-default bg-surface-raised shadow-card">
          <div class="flex h-14 items-center justify-between border-b border-line-default px-4">
            <div class="text-card-title text-content-strong">General settings</div>
            <%= if authorized?(:"device:update", @current_scope) do %>
              <.button style="primary" type="submit">
                <.icon name="save" /> Save changes
              </.button>
            <% end %>
          </div>
          <div class="flex gap-6 p-4">
            <div class="flex w-1/2 flex-col gap-6">
              <.input field={@settings_form[:description]} label="Description" placeholder="eg. sensor hub at customer X" phx-debounce="blur" />

              <.tag_input field={@settings_form[:tags]} label="Tags" placeholder="eg. batch-123" available_tags={@available_tags} />
            </div>

            <div class="flex w-1/2 flex-col gap-2">
              <.input field={@settings_form[:connecting_code]} label="First connect code" type="textarea" rows="10" phx-debounce="2000" />
              <div class="text-xs tracking-wide text-content-muted">Make sure this is valid Elixir and will not crash the device</div>
            </div>
          </div>
        </div>
      </.form>

      <div class="flex w-full flex-col rounded-md border border-line-default bg-surface-raised shadow-card">
        <div class="flex h-14 items-center justify-between border-b border-line-default px-4">
          <div class="text-card-title text-content-strong">Firmware updates</div>
        </div>
        <div class="flex flex-col gap-1 px-4 py-2">
          <div class="flex h-16 items-center gap-6 p-2">
            <div class="flex h-8 shrink-0 items-center rounded-full border border-line-default bg-base-800 px-2 py-1">
              <input
                id="managed-updates-allowed"
                name="managed-updates-allowed"
                type="checkbox"
                phx-click="toggle-managed-updates-allowed"
                checked={@device.managed_updates_allowed}
                disabled={!authorized?(:"device:toggle-updates", @current_scope)}
              />
            </div>
            <div class="flex flex-col">
              <div class="font-medium text-content-body">Let the device choose its update mode</div>
              <div class="font-light text-content-muted">
                The device may move itself between automatic and device managed.
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="flex w-full flex-col rounded-md border border-line-default bg-surface-raised shadow-card">
        <div class="flex h-14 items-center justify-between border-b border-line-default px-4">
          <div class="text-card-title text-content-strong">Extensions</div>
        </div>
        <div class="flex flex-col gap-1 px-4 py-2">
          <div :for={{key, description} <- available_extensions()} class="flex h-16 items-center gap-6 p-2">
            <div class="flex h-8 items-center rounded-full border border-line-default bg-base-800 px-2 py-1">
              <input
                id={"extension-#{key}"}
                name={key}
                type="checkbox"
                phx-click="update-extension"
                phx-value-extension={key}
                checked={@device.extensions[key]}
                disabled={not @device.product.extensions[key] or !authorized?(:"device:update", @current_scope)}
              />
            </div>
            <div class="flex flex-col">
              <div class="flex gap-2">
                <div class="font-medium text-content-body">
                  {Extensions.display_name(key)}
                </div>
                <div :if={Map.get(@device.product.extensions, key) != true} class="text-alert">
                  - Extension is disabled at the product level.
                </div>
              </div>
              <div class="font-light text-content-muted">
                {description}
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="flex w-full flex-col rounded-md border border-line-default bg-surface-raised shadow-card">
        <div class="flex h-14 items-center justify-between border-b border-line-default px-4">
          <div class="text-card-title text-content-strong">Certificates</div>
          <div>
            <form id="upload-certificate" phx-change="validate-cert" phx-drop-target={@uploads.certificate.ref}>
              <.button type="label" for={@uploads.certificate.ref}>
                <.icon name="save" /> Upload certificate
              </.button>
              <.live_file_input upload={@uploads.certificate} class="hidden" />
            </form>
          </div>
        </div>
        <div class="flex flex-col gap-1 px-4 py-2">
          <div :if={Enum.empty?(@device.device_certificates)} class="flex h-16 items-center gap-6 p-2">
            <div>No certificates have been uploaded.</div>
          </div>
          <div :for={certificate <- @device.device_certificates} class="flex h-16 items-center gap-6 p-2">
            <div class="flex h-8 items-center rounded-full border border-line-default bg-base-800 px-2 py-1">
              <span class="lucide-file-badge size-4 text-content-muted" aria-hidden="true"></span>
            </div>
            <div class="grow">
              <div class="text-content-body">Serial: {Utils.format_serial(certificate.serial)}</div>
              <div class="flex gap-2">
                <div class="text-xs tracking-wide text-content-muted">
                  <span>Last used:</span>
                  <%= if !is_nil(certificate.last_used) do %>
                    <span>{DateTimes.from_now(certificate.last_used)}</span>
                  <% else %>
                    <span>Never</span>
                  <% end %>
                </div>

                <div class="text-xs tracking-wide text-content-muted">
                  <span>Not before:</span>
                  <.local_datetime at={certificate.not_before} time_zone={@time_zone} format={:date} zone_label={false} />
                </div>

                <div class="text-xs tracking-wide text-content-muted">
                  <span>Not after:</span>
                  <.local_datetime at={certificate.not_after} time_zone={@time_zone} format={:date} zone_label={false} />
                </div>

                <div class="text-xs tracking-wide text-content-muted">
                  <span>Signer CA:</span>
                  <.signer_ca signer_ca={@signer_cas[certificate.aki]} org={@org} />
                </div>
              </div>
            </div>
            <div class="flex gap-2">
              <.button type="link" href={~p"/org/#{@org}/#{@product}/devices/#{@device}/certificate/#{certificate}/download"} download square aria-label="Download certificate">
                <.icon name="save" />
              </.button>
              <.button
                style="danger"
                type="button"
                square
                aria-label="Delete certificate"
                phx-click="delete-certificate"
                phx-value-serial={certificate.serial}
                data-confirm="Are you sure you want to delete this certificate?"
              >
                <span class="lucide-trash size-4 text-alert" aria-hidden="true"></span>
              </.button>
            </div>
          </div>
        </div>
      </div>

      <div :if={@shared_secrets_enabled} id="shared-secrets" class="flex w-full flex-col rounded-md border border-line-default bg-surface-raised shadow-card">
        <div class="flex h-14 items-center justify-between border-b border-line-default px-4">
          <div class="text-card-title text-content-strong">Shared secrets</div>
          <.button
            :if={is_nil(@device.deleted_at) && authorized?(:"device:update", @current_scope)}
            phx-click="create-shared-secret"
            aria-label="Create a shared secret"
          >
            <.icon name="add" />Create shared secret
          </.button>
        </div>
        <div :if={@new_shared_secret} class="flex flex-col gap-3 border-b border-line-default p-4">
          <p class="text-sm text-warning">
            Copy the secret now. It is only shown once, and cannot be retrieved again.
          </p>
          <div class="text-sm text-content-body">Key: <code>{@new_shared_secret.key}</code></div>
          <input type="hidden" id="shared-secret-new" value={@new_shared_secret.secret} />
          <div class="flex gap-3">
            <.button id="shared-secret-new-button" value="new" phx-hook="SharedSecretClipboardClick" aria-label="Copy secret">
              Copy secret
            </.button>
            <.button phx-click="dismiss-shared-secret">Done</.button>
          </div>
        </div>
        <div class="flex flex-col gap-1 px-4 py-2">
          <div :if={Enum.empty?(@shared_secrets)} class="flex h-16 items-center gap-6 p-2">
            <div>No shared secrets have been created.</div>
          </div>
          <div :if={Enum.any?(@shared_secrets)} class="flex items-center gap-6 px-2 pt-2 text-xs tracking-wide text-content-muted">
            <div class="grow">Key</div>
            <div class="w-24 text-center">Created by</div>
            <div class="w-24 text-center">Deactivated by</div>
            <div class="w-28"></div>
          </div>
          <div :for={auth <- @shared_secrets} class="flex h-16 items-center gap-6 p-2">
            <div class={["grow", auth.deactivated_at && "opacity-60"]}>
              <div class="text-content-body"><code>{auth.key}</code></div>
              <div class="text-xs tracking-wide text-content-muted">
                <span :if={auth.last_used}>Last used {DateTimes.from_now(auth.last_used)}</span>
                <span :if={is_nil(auth.last_used)}>Never used</span>
              </div>
            </div>
            <div class="flex w-24 justify-center">
              <.shared_secret_change id={"#{auth.key}-created"} action="Created" user={auth.created_by} at={auth.inserted_at} time_zone={@time_zone} />
            </div>
            <div class="flex w-24 justify-center">
              <.shared_secret_change
                :if={auth.deactivated_at}
                id={"#{auth.key}-deactivated"}
                action="Deactivated"
                user={auth.deactivated_by}
                at={auth.deactivated_at}
                time_zone={@time_zone}
              />
            </div>
            <div class="flex w-28 justify-end">
              <.button
                :if={is_nil(auth.deactivated_at) && is_nil(@device.deleted_at) && authorized?(:"device:update", @current_scope)}
                phx-click="deactivate-shared-secret"
                phx-value-key={auth.key}
                data-confirm="Are you sure you want to deactivate this shared secret? Connections made with it will be closed, and the device can no longer connect with it."
                aria-label="Deactivate shared secret"
              >
                Deactivate
              </.button>
              <.badge :if={auth.deactivated_at}>Deactivated</.badge>
            </div>
          </div>
        </div>
      </div>

      <div :if={@device.deleted_at && authorized?(:"device:update", @current_scope)} class="flex w-full flex-col rounded-md border border-line-default bg-surface-raised shadow-card">
        <div class="p-4 pb-0 text-content-body">
          The device has been disabled. Attempts to connect to NervesHub will be blocked.
        </div>
        <div class="flex items-center gap-6 border-line-default p-4">
          <div>
            <.button style="danger" type="button" phx-click="destroy-device" data-confirm="Are you sure you want to permanently delete this device?">
              <span class="lucide-trash size-4 text-alert" aria-hidden="true"></span>

              <span class="text-sm font-medium text-alert">Permanently delete device</span>
            </.button>
          </div>
          <div class="text-content-body">or</div>
          <div>
            <.button type="button" phx-click="restore-device" data-confirm="Are you sure you want to restore this device?">
              <span class="lucide-rotate-ccw size-4 text-content-muted" aria-hidden="true"></span>

              <span class="text-sm font-medium text-content-body">Restore device</span>
            </.button>
          </div>
        </div>
      </div>

      <div :if={!@device.deleted_at && authorized?(:"device:update", @current_scope)} class="flex w-full flex-col rounded-md border border-line-default bg-surface-raised shadow-card">
        <div class="flex items-center gap-6 border-t border-line-default p-4">
          <div class="shrink-0">
            <.button
              style="danger"
              type="button"
              phx-click="delete-device"
              data-confirm="Are you sure you want to delete this device? It will be disconnected and removed from its deployment group, and any certificates associated with it will be deleted."
            >
              <span class="lucide-trash size-4 text-alert" aria-hidden="true"></span>
              <span class="text-sm font-medium text-alert">Delete device</span>
            </.button>
          </div>
          <div>
            The device will be disabled and unable to connect to the NervesHub server.
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr(:signer_ca, :any, required: true)
  attr(:org, :map, required: true)

  defp signer_ca(%{signer_ca: nil} = assigns) do
    ~H"""
    <span>Unknown</span>
    """
  end

  defp signer_ca(assigns) do
    ~H"""
    <.link navigate={~p"/org/#{@org}/settings/certificates/#{@signer_ca}"} class="underline hover:text-content-body">
      {CAHelpers.label(@signer_ca)}
    </.link>
    """
  end

  attr(:id, :string, required: true)
  attr(:action, :string, required: true)
  attr(:user, :any, required: true, doc: "who made the change, or nil when no user did")
  attr(:at, :any, required: true)
  attr(:time_zone, :string, required: true)

  # Who changed a shared secret, as an avatar with the details on hover.
  defp shared_secret_change(assigns) do
    ~H"""
    <.tooltip id={@id} placement="top" class="flex items-center">
      <CoreComponents.user_avatar :if={@user} user={@user} />
      <div
        :if={!@user}
        class="relative inline-flex size-8 items-center justify-center rounded-full bg-base-800 dark:bg-base-600"
      >
        <span class="font-medium text-content-muted dark:text-content-body">?</span>
      </div>
      <:content>
        {@action}<span :if={@user}> by {@user.name}</span> on <.local_datetime at={@at} time_zone={@time_zone} format={:date} zone_label={false} />
      </:content>
    </.tooltip>
    """
  end

  def hooked_event("validate-device-settings", %{"device" => device_params}, socket) do
    changeset = Device.changeset(socket.assigns.device, device_params)

    socket
    |> assign(:settings_form, to_form(changeset, action: :validate))
    |> halt()
  end

  def hooked_event("update-device-settings", %{"device" => device_params}, socket) do
    authorized!(:"device:update", socket.assigns.current_scope)

    %{device: device, user: user} = socket.assigns

    message = "User #{user.name} updated device #{device.identifier}"

    case Devices.update_device_with_audit(device, device_params, user, message) do
      {:ok, device} ->
        socket
        |> assign(:device, device)
        |> put_flash(:info, "Device updated.")
        |> halt()

      {:error, :update_with_audit, changeset, _} ->
        error =
          if Keyword.has_key?(changeset.errors, :deleted_at) do
            "Device cannot be updated because it has been deleted. Please restore the device to make changes."
          else
            "We couldn't save your changes. Please contact support if this happens again."
          end

        socket
        |> put_flash(:error, error)
        |> assign(:settings_form, to_form(changeset))
        |> halt()

      {:error, _, _, _} ->
        socket
        |> put_flash(:error, "An unknown error occurred, please contact support.")
        |> halt()
    end
  end

  def hooked_event("delete-device", _, socket) do
    authorized!(:"device:delete", socket.assigns.current_scope)

    {:ok, device} = Devices.delete_device(socket.assigns.device)

    send(self(), :reload_device)

    socket
    |> assign(:device, device)
    |> put_flash(:info, "The device has been deleted. This action can be undone.")
    |> halt()
  end

  def hooked_event("restore-device", _, socket) do
    authorized!(:"device:restore", socket.assigns.current_scope)

    {:ok, device} = Devices.restore_device(socket.assigns.device)

    send(self(), :reload_device)

    socket
    |> assign(:device, device)
    |> put_flash(:info, "The device has been restored.")
    |> halt()
  end

  def hooked_event("destroy-device", _, socket) do
    %{current_scope: current_scope, device: device} = socket.assigns

    authorized!(:"device:destroy", current_scope)

    {:ok, _device} = Devices.destroy_device(device)

    send(self(), :reload_device)

    socket
    |> put_flash(:info, "Device permanently destroyed successfully.")
    |> push_navigate(to: ~p"/org/#{current_scope.org}/#{current_scope.product}/devices")
    |> halt()
  end

  # A phx-change handler is required when using live uploads.
  def hooked_event("validate-cert", _, socket), do: {:halt, socket}

  def hooked_event("delete-certificate", %{"serial" => serial}, %{assigns: %{device: device}} = socket) do
    device = %{device_certificates: certs} = Certificates.preload_device_certificates(device)

    db_cert = Enum.find(certs, &(&1.serial == serial))

    case Certificates.delete_device_certificate(db_cert) do
      {:ok, _db_cert} ->
        updated_certs = Enum.reject(certs, &(&1.serial == serial))

        socket
        |> put_flash(:info, "Certificate deleted.")
        |> assign(device: %{device | device_certificates: updated_certs})
        |> halt()

      _ ->
        socket
        |> put_flash(:error, "Failed to delete certificate, please contact support.")
        |> halt()
    end
  end

  def hooked_event("create-shared-secret", _params, %{assigns: %{device: %{deleted_at: nil} = device}} = socket) do
    authorized!(:"device:update", socket.assigns.current_scope)

    case Devices.issue_shared_secret_auth(device, socket.assigns.user) do
      {:ok, auth} ->
        socket
        |> assign(:new_shared_secret, Map.take(auth, [:key, :secret]))
        |> assign(:shared_secrets, Devices.list_shared_secret_auths(device))
        |> halt()

      {:error, :shared_secrets_not_enabled} ->
        socket
        |> put_flash(:error, "Shared secrets are not enabled on this platform.")
        |> halt()

      {:error, _changeset} ->
        socket
        |> put_flash(:error, "We couldn't create a shared secret. Please contact support if this happens again.")
        |> halt()
    end
  end

  def hooked_event("dismiss-shared-secret", _params, socket) do
    socket
    |> assign(:new_shared_secret, nil)
    |> halt()
  end

  def hooked_event(
        "deactivate-shared-secret",
        %{"key" => key},
        %{assigns: %{device: %{deleted_at: nil} = device}} = socket
      ) do
    authorized!(:"device:update", socket.assigns.current_scope)

    socket =
      case Devices.deactivate_shared_secret_auth(device, key, socket.assigns.user) do
        {:ok, _auth} ->
          put_flash(socket, :info, "The shared secret has been deactivated, and connections made with it closed.")

        {:error, :not_found} ->
          put_flash(socket, :error, "That shared secret is no longer active.")
      end

    socket
    |> assign(:shared_secrets, Devices.list_shared_secret_auths(device))
    |> halt()
  end

  def hooked_event(event, _params, socket) when event in ["create-shared-secret", "deactivate-shared-secret"] do
    socket
    |> put_flash(:error, "The device is deleted and must be restored to change its shared secrets.")
    |> halt()
  end

  def hooked_event("toggle-managed-updates-allowed", params, socket) do
    authorized!(:"device:toggle-updates", socket.assigns.current_scope)

    %{device: device, user: user} = socket.assigns
    enabled = params["value"] == "on"

    case Updates.set_managed_updates_allowed(device, enabled, user) do
      {:ok, device} ->
        socket
        |> assign(:device, device)
        |> put_flash(:info, "The device #{(enabled && "may") || "may no longer"} choose its own update mode.")
        |> halt()

      _error ->
        socket
        |> put_flash(:error, "We couldn't save that change. Please contact support if this happens again.")
        |> halt()
    end
  end

  def hooked_event("update-extension", %{"extension" => extension} = params, socket) do
    authorized!(:"device:update", socket.assigns.current_scope)

    value = params["value"]
    available = Extensions.list() |> Enum.map(&to_string/1)

    result =
      case {extension in available, value} do
        {true, "on"} ->
          Devices.enable_extension_setting(socket.assigns.device, extension)

        {true, _} ->
          Devices.disable_extension_setting(socket.assigns.device, extension)
      end

    case result do
      {:ok, _pf} ->
        send(self(), :reload_device)

        put_flash(
          socket,
          :info,
          "The #{Extensions.display_name(extension)} extension was successfully #{(value == "on" && "enabled") || "disabled"}."
        )

      {:error, _changeset} ->
        put_flash(
          socket,
          :error,
          "There was an unexpected error when updating the #{Extensions.display_name(extension)} extension. Please contact support."
        )
    end
    |> halt()
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  def hooked_info(_event, socket), do: {:cont, socket}

  def hooked_async(_name, _async_fun_result, socket), do: {:cont, socket}

  def handle_progress(:certificate, %{done?: true} = entry, socket) do
    socket = consume_uploaded_entry(socket, entry, &import_cert(socket, &1.path))

    {:noreply, socket}
  end

  def handle_progress(:certificate, _entry, socket), do: {:noreply, socket}

  defp import_cert(%{assigns: %{device: device}} = socket, path) do
    with {:ok, pem_or_der} <- File.read(path),
         {:ok, otp_cert} <- Certificate.from_pem_or_der(pem_or_der),
         {:ok, _db_cert} <- Certificates.create_device_certificate(device, otp_cert) do
      updated = Certificates.preload_device_certificates(device)

      assign(socket, :device, updated)
      |> put_flash(:info, "Certificate Upload Successful")
      |> ok()
    else
      {:error, :malformed} ->
        {:ok, put_flash(socket, :error, "Incorrect filetype or malformed certificate")}

      {:error, %Ecto.Changeset{errors: errors}} ->
        formatted =
          Enum.map_join(errors, "\n", fn {field, {msg, _}} ->
            ["* ", to_string(field), " ", msg]
          end)

        socket
        |> put_flash(:error, IO.iodata_to_binary(["Failed to save:\n", formatted]))
        |> ok()

      err ->
        socket
        |> put_flash(:error, "Unknown file error - #{inspect(err)}")
        |> ok()
    end
  end

  defp available_extensions() do
    for extension <- Extensions.list(),
        into: %{},
        do: {extension, Extensions.module(extension).description()}
  end
end
