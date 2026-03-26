defmodule NervesHubWeb.Components.DevicePage.SettingsTab do
  use NervesHubWeb, tab_component: :settings

  alias NervesHub.Certificate
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Extensions
  alias NervesHub.Repo
  alias NervesHubWeb.Components.Utils
  alias NervesHubWeb.LayoutView.DateTimeFormat

  def tab_params(_params, _uri, socket) do
    changeset = Ecto.Changeset.change(socket.assigns.device)

    socket
    |> assign(:settings_form, to_form(changeset))
    |> allow_upload(:certificate,
      accept: :any,
      auto_upload: true,
      max_entries: 1,
      progress: &handle_progress/3
    )
    |> cont()
  end

  def render(assigns) do
    device = Repo.preload(assigns.device, :device_certificates, force: true)

    assigns = Map.put(assigns, :device, device)

    ~H"""
    <div
      id="settings-tab"
      phx-mounted={JS.remove_class("opacity-0")}
      class="phx-click-loading:opacity-50 tab-content flex flex-col items-start justify-between gap-4 p-6 opacity-0 transition-all duration-500"
    >
      <.form id="settings-form" for={@settings_form} class="w-full" phx-change="validate-device-settings" phx-submit="update-device-settings">
        <div class="bg-base-900 border-base-700 flex w-full flex-col rounded border">
          <div class="border-base-700 flex h-14 items-center justify-between border-b px-4">
            <div class="text-base font-medium text-neutral-50">General settings</div>
            <%= if authorized?(:"device:update", @current_scope) do %>
              <.button style="secondary" type="submit">
                <.icon name="save" /> Save changes
              </.button>
            <% end %>
          </div>
          <div class="flex gap-6 p-6">
            <div class="flex w-1/2 flex-col gap-6">
              <%!-- <div phx-feedback-for={f[:description].name}>
                <label for={@for} class="block text-sm font-semibold leading-6 text-base-800">
                  Description
                </label>
                <input
                  type={@type}
                  name={@name}
                  id={@id}
                  value={Phoenix.HTML.Form.normalize_value(@type, @value)}
                  class={[
                    "mt-2 block w-full rounded-lg text-base-900 focus:ring-0 sm:text-sm sm:leading-6",
                    "phx-no-feedback:border-base-300 phx-no-feedback:focus:border-base-400",
                    @errors == [] && "border-base-300 focus:border-base-400",
                    @errors != [] && "border-rose-400 focus:border-rose-400"
                  ]}
                />
                <p :for={msg <- @errors} class="mt-3 flex gap-3 text-sm leading-6 text-rose-600 phx-no-feedback:hidden">
                  <.icon name="hero-exclamation-circle-mini" class="mt-0.5 h-5 w-5 flex-none" />
                  <%= render_slot(@inner_block) %>
                </p>
              </div> --%>

              <.input field={@settings_form[:description]} label="Description" placeholder="eg. sensor hub at customer X" phx-debounce="blur" />

              <.input field={@settings_form[:tags]} value={Utils.tags_to_string(@settings_form[:tags])} label="Tags" placeholder="eg. batch-123" phx-debounce="blur" />
            </div>

            <div class="flex w-1/2 flex-col gap-2">
              <.input field={@settings_form[:connecting_code]} label="First connect code" type="textarea" rows="10" phx-debounce="2000" />
              <div class="text-base-400 text-xs tracking-wide">Make sure this is valid Elixir and will not crash the device</div>
            </div>
          </div>
        </div>
      </.form>

      <div class="bg-base-900 border-base-700 flex w-full flex-col rounded border">
        <div class="border-base-700 flex h-14 items-center justify-between border-b px-4">
          <div class="text-base font-medium text-neutral-50">Extensions</div>
        </div>
        <div class="flex flex-col gap-1 px-4 py-2">
          <div :for={{key, description} <- available_extensions()} class="flex h-16 items-center gap-6 p-2">
            <div class="bg-base-800 border-base-700 flex h-8 items-center rounded-full border px-2 py-1">
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
                <div class="text-base-300 font-medium">
                  {format_key(key)}
                </div>
                <div :if={Map.get(@device.product.extensions, key) != true} class="text-alert">
                  - Extension is disabled at the product level.
                </div>
              </div>
              <div class="text-base-300">
                {description}
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="bg-base-900 border-base-700 flex w-full flex-col rounded border">
        <div class="border-base-700 flex h-14 items-center justify-between border-b px-4">
          <div class="text-base font-medium text-neutral-50">Certificates</div>
          <div>
            <form id="upload-certificate" phx-change="validate-cert" phx-drop-target={@uploads.certificate.ref}>
              <div class="bg-base-800 border-base-600 flex gap-2 rounded border px-3 py-1.5 hover:cursor-pointer">
                <svg class="size-5" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                  <path
                    d="M6.66671 16.6667H5.00004C4.07957 16.6667 3.33337 15.9205 3.33337 15V5.00004C3.33337 4.07957 4.07957 3.33337 5.00004 3.33337H12.643C13.085 3.33337 13.509 3.50897 13.8215 3.82153L16.1786 6.17855C16.4911 6.49111 16.6667 6.91504 16.6667 7.35706V15C16.6667 15.9205 15.9205 16.6667 15 16.6667H13.3334M6.66671 16.6667V12.5H13.3334V16.6667M6.66671 16.6667H13.3334M6.66671 6.66671V9.16671H9.16671V6.66671H6.66671Z"
                    stroke="#A1A1AA"
                    stroke-width="1.2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  />
                </svg>
                <label for={@uploads.certificate.ref} class="text-base-300 text-sm font-medium hover:cursor-pointer">Upload certificate</label>
                <.live_file_input upload={@uploads.certificate} class="hidden" />
              </div>
            </form>
          </div>
        </div>
        <div class="flex flex-col gap-1 px-4 py-2">
          <div :if={Enum.empty?(@device.device_certificates)} class="flex h-16 items-center gap-6 p-2">
            <div>No certificates have been uploaded.</div>
          </div>
          <div :for={certificate <- @device.device_certificates} class="flex h-16 items-center gap-6 p-2">
            <div class="bg-base-800 border-base-700 flex h-8 items-center rounded-full border px-2 py-1">
              <svg class="size-4" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path
                  d="M8 6L7 7L8 8M11 6L12 7L11 8M15 7H17M7 11H9M12 11H17M17 14H16M13 14H7M6 21H18C19.1046 21 20 20.1046 20 19V5C20 3.89543 19.1046 3 18 3H6C4.89543 3 4 3.89543 4 5V19C4 20.1046 4.89543 21 6 21Z"
                  stroke="#A1A1AA"
                  stroke-width="1.2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
              </svg>
            </div>
            <div class="grow">
              <div class="text-base-300">Serial: {Utils.format_serial(certificate.serial)}</div>
              <div class="flex gap-2">
                <div class="text-base-400 text-xs tracking-wide">
                  <span>Last used:</span>
                  <%= if !is_nil(certificate.last_used) do %>
                    <span>{DateTimeFormat.from_now(certificate.last_used)}</span>
                  <% else %>
                    <span>Never</span>
                  <% end %>
                </div>

                <div class="text-base-400 text-xs tracking-wide">
                  <span>Not before:</span>
                  <span>{Calendar.strftime(certificate.not_before, "%Y-%m-%d")}</span>
                </div>

                <div class="text-base-400 text-xs tracking-wide">
                  <span>Not after:</span>
                  <span>{Calendar.strftime(certificate.not_after, "%Y-%m-%d")}</span>
                </div>
              </div>
            </div>
            <div class="flex gap-2">
              <.link class="bg-base-800 border-base-600 flex gap-2 rounded border px-3 py-1.5" href={~p"/org/#{@org}/#{@product}/devices/#{@device}/certificate/#{certificate}/download"} download>
                <svg class="size-5" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                  <path
                    d="M6.66671 16.6667H5.00004C4.07957 16.6667 3.33337 15.9205 3.33337 15V5.00004C3.33337 4.07957 4.07957 3.33337 5.00004 3.33337H12.643C13.085 3.33337 13.509 3.50897 13.8215 3.82153L16.1786 6.17855C16.4911 6.49111 16.6667 6.91504 16.6667 7.35706V15C16.6667 15.9205 15.9205 16.6667 15 16.6667H13.3334M6.66671 16.6667V12.5H13.3334V16.6667M6.66671 16.6667H13.3334M6.66671 6.66671V9.16671H9.16671V6.66671H6.66671Z"
                    stroke="#A1A1AA"
                    stroke-width="1.2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  />
                </svg>
              </.link>
              <button
                class="bg-base-800 border-alert flex gap-2 rounded border px-3 py-1.5"
                type="button"
                phx-click="delete-certificate"
                phx-value-serial={certificate.serial}
                data-confirm="Are you sure you want to delete this certificate?"
              >
                <svg class="size-5" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                  <path
                    d="M12.4999 5.83337H7.49992M12.4999 5.83337H14.9999M12.4999 5.83337C12.4999 4.45266 11.3806 3.33337 9.99992 3.33337C8.61921 3.33337 7.49992 4.45266 7.49992 5.83337M7.49992 5.83337H4.99992M3.33325 5.83337H4.99992M4.99992 5.83337V15C4.99992 15.9205 5.74611 16.6667 6.66659 16.6667H13.3333C14.2537 16.6667 14.9999 15.9205 14.9999 15V5.83337M14.9999 5.83337H16.6666M8.33325 9.16671V13.3334M11.6666 13.3334V9.16671"
                    stroke="#EF4444"
                    stroke-width="1.2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  />
                </svg>
              </button>
            </div>
          </div>
        </div>
      </div>

      <div :if={@device.deleted_at && authorized?(:"device:update", @current_scope)} class="bg-base-900 border-base-700 flex w-full flex-col rounded border">
        <div class="text-base-300 p-6 pb-0">
          The device has been disabled. Attempts to connect to NervesHub will be blocked.
        </div>
        <div class="border-base-700 flex items-center gap-6 p-6">
          <div>
            <button
              class="bg-base-800 border-alert flex gap-2 rounded border px-3 py-1.5"
              type="button"
              phx-click="destroy-device"
              data-confirm="Are you sure you want to permanently delete this device?"
            >
              <svg class="stroke-alert size-5" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path
                  d="M12.4999 5.83337H7.49992M12.4999 5.83337H14.9999M12.4999 5.83337C12.4999 4.45266 11.3806 3.33337 9.99992 3.33337C8.61921 3.33337 7.49992 4.45266 7.49992 5.83337M7.49992 5.83337H4.99992M3.33325 5.83337H4.99992M4.99992 5.83337V15C4.99992 15.9205 5.74611 16.6667 6.66659 16.6667H13.3333C14.2537 16.6667 14.9999 15.9205 14.9999 15V5.83337M14.9999 5.83337H16.6666M8.33325 9.16671V13.3334M11.6666 13.3334V9.16671"
                  stroke-width="1.2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
              </svg>

              <span class="text-alert text-sm font-medium">Permanently delete device</span>
            </button>
          </div>
          <div class="text-base-300">or</div>
          <div>
            <button class="bg-base-800 border-base-600 flex gap-2 rounded border px-3 py-1.5" type="button" phx-click="restore-device" data-confirm="Are you sure you want to restore this device?">
              <svg class="size-5" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path
                  d="M8.5 18.9999H5.39903C3.87406 18.9999 2.91012 17.3617 3.65071 16.0287L7 9.99994M7 9.99994L3 11.9999M7 9.99994L8 13.9999M18.9999 13.9999L20.1987 16.0122C20.9929 17.3454 20.0323 19.0358 18.4805 19.0358L12.768 19.0358M12.768 19.0358L16 21.9999M12.768 19.0358L16 15.9999M8.5 6.99994L10.5883 3.86749C11.4401 2.58975 13.3545 2.70894 14.0413 4.08246L17 9.99994M17 9.99994L18 5.99994M17 9.99994L13 8.99994"
                  stroke="#A1A1AA"
                  stroke-width="1.2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
              </svg>

              <span class="text-base-300 text-sm font-medium">Restore device</span>
            </button>
          </div>
        </div>
      </div>

      <div :if={!@device.deleted_at && authorized?(:"device:update", @current_scope)} class="bg-base-900 border-base-700 flex w-full flex-col rounded border">
        <div class="border-base-700 flex items-center gap-6 border-t p-6">
          <div>
            <button
              class="bg-base-800 border-alert hover:bg-alert-soft flex gap-2 rounded border px-3 py-1.5"
              type="button"
              phx-click="delete-device"
              data-confirm="Are you sure you want to delete this device? This will also delete any certificates associated with the device."
            >
              <svg class="stroke-alert size-5" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path
                  d="M12.4999 5.83337H7.49992M12.4999 5.83337H14.9999M12.4999 5.83337C12.4999 4.45266 11.3806 3.33337 9.99992 3.33337C8.61921 3.33337 7.49992 4.45266 7.49992 5.83337M7.49992 5.83337H4.99992M3.33325 5.83337H4.99992M4.99992 5.83337V15C4.99992 15.9205 5.74611 16.6667 6.66659 16.6667H13.3333C14.2537 16.6667 14.9999 15.9205 14.9999 15V5.83337M14.9999 5.83337H16.6666M8.33325 9.16671V13.3334M11.6666 13.3334V9.16671"
                  stroke-width="1.2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
              </svg>
              <span class="text-alert text-sm font-medium">Delete device</span>
            </button>
          </div>
          <div>
            The device will be disabled and unable to connect to the NervesHub server.
          </div>
        </div>
      </div>
    </div>
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
    device = %{device_certificates: certs} = Repo.preload(device, :device_certificates)

    db_cert = Enum.find(certs, &(&1.serial == serial))

    case Devices.delete_device_certificate(db_cert) do
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

  def hooked_event("update-extension", %{"extension" => extension} = params, socket) do
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
          "The #{format_key(extension)} extension was successfully #{(value == "on" && "enabled") || "disabled"}."
        )

      {:error, _changeset} ->
        put_flash(
          socket,
          :error,
          "There was an unexpected error when updating the #{format_key(extension)} extension. Please contact support."
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
         {:ok, _db_cert} <- Devices.create_device_certificate(device, otp_cert) do
      updated = Repo.preload(device, :device_certificates)

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

  def format_key(key) do
    to_string(key)
    |> Phoenix.Naming.humanize()
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
