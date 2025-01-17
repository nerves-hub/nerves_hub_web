defmodule NervesHubWeb.Components.DevicePage.Settings do
  use NervesHubWeb, :live_component

  alias NervesHubWeb.Components.Utils
  alias NervesHubWeb.LayoutView.DateTimeFormat

  alias NervesHub.Certificate
  alias NervesHub.Devices
  alias NervesHub.Extensions

  def update(assigns, socket) do
    device =
      Devices.get_device_by_identifier!(
        assigns.org,
        assigns.device.identifier,
        :device_certificates
      )
      |> Devices.preload_product()

    changeset = Ecto.Changeset.change(assigns.device)

    socket
    |> assign(assigns)
    |> assign(:device, device)
    |> assign(:settings_form, to_form(changeset))
    |> assign(:available_extensions, extensions())
    |> allow_upload(:certificate,
      accept: :any,
      auto_upload: true,
      max_entries: 1,
      progress: &handle_progress/3
    )
    |> ok()
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-start justify-between gap-4 p-6">
      <.form for={@settings_form} class="w-full" phx-submit="update-device-settings" phx-target={@myself}>
        <div class="flex flex-col w-full bg-zinc-900 border border-zinc-700 rounded">
          <div class="flex justify-between items-center h-14 px-4 border-b border-zinc-700">
            <div class="text-base text-neutral-50 font-medium">General settings</div>
            <div>
              <button class="flex px-3 py-1.5 gap-2 rounded bg-zinc-800 border border-zinc-600" type="submit">
                <svg class="w-5 h-5" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                  <path
                    d="M6.66671 16.6667H5.00004C4.07957 16.6667 3.33337 15.9205 3.33337 15V5.00004C3.33337 4.07957 4.07957 3.33337 5.00004 3.33337H12.643C13.085 3.33337 13.509 3.50897 13.8215 3.82153L16.1786 6.17855C16.4911 6.49111 16.6667 6.91504 16.6667 7.35706V15C16.6667 15.9205 15.9205 16.6667 15 16.6667H13.3334M6.66671 16.6667V12.5H13.3334V16.6667M6.66671 16.6667H13.3334M6.66671 6.66671V9.16671H9.16671V6.66671H6.66671Z"
                    stroke="#A1A1AA"
                    stroke-width="1.2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  />
                </svg>
                <span class="text-sm font-medium text-zinc-300">Save changes</span>
              </button>
            </div>
          </div>
          <div class="flex p-6 gap-6">
            <div class="w-1/2 flex flex-col gap-6">
              <%!-- <div phx-feedback-for={f[:description].name}>
                <label for={@for} class="block text-sm font-semibold leading-6 text-zinc-800">
                  Description
                </label>
                <input
                  type={@type}
                  name={@name}
                  id={@id}
                  value={Phoenix.HTML.Form.normalize_value(@type, @value)}
                  class={[
                    "mt-2 block w-full rounded-lg text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6",
                    "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
                    @errors == [] && "border-zinc-300 focus:border-zinc-400",
                    @errors != [] && "border-rose-400 focus:border-rose-400"
                  ]}
                />
                <p :for={msg <- @errors} class="mt-3 flex gap-3 text-sm leading-6 text-rose-600 phx-no-feedback:hidden">
                  <.icon name="hero-exclamation-circle-mini" class="mt-0.5 h-5 w-5 flex-none" />
                  <%= render_slot(@inner_block) %>
                </p>
              </div> --%>

              <NervesHubWeb.CoreComponents.input field={@settings_form[:description]} label="Description" placeholder="eg. sensor hub at customer X" />

              <NervesHubWeb.CoreComponents.input field={@settings_form[:tags]} value={tags_to_string(@settings_form[:tags])} label="Tags" placeholder="eg. batch-123" />
            </div>

            <div class="w-1/2 flex flex-col gap-2">
              <NervesHubWeb.CoreComponents.input field={@settings_form[:first_connect_code]} label="First connect code" type="textarea" rows="10" />
              <div class="text-xs tracking-wide text-zinc-400">Make sure this is valid Elixir and will not crash the device</div>
            </div>
          </div>
        </div>
      </.form>

      <div class="flex flex-col w-full bg-zinc-900 border border-zinc-700 rounded">
        <div class="flex justify-between items-center h-14 px-4 border-b border-zinc-700">
          <div class="text-base text-neutral-50 font-medium">Extensions</div>
        </div>
        <div class="py-2 px-4 flex flex-col gap-1">
          <div :for={{key, description} <- @available_extensions} class="flex items-center gap-6 h-16 p-2">
            <div class="flex items-center h-8 py-1 px-2 bg-zinc-800 border border-zinc-700 rounded-full">
              <input
                id={"extension-#{key}"}
                name={key}
                type="checkbox"
                phx-click="update-extension"
                phx-value-extension={key}
                phx-target={@myself}
                checked={@device.extensions[key]}
                disabled={not @device.product.extensions[key] or !authorized?(:"device:update", @org_user)}
              />
            </div>
            <div class="flex flex-col">
              <div class="flex gap-2">
                <div class="w-14 font-medium text-zinc-300">
                  {String.capitalize(to_string(key))}
                </div>
                <div :if={Map.get(@device.product.extensions, key) != true} class="text-red-500">
                  Extension is disabled at the product level.
                </div>
              </div>
              <div class="text-zinc-300">
                {description}
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="flex flex-col w-full bg-zinc-900 border border-zinc-700 rounded">
        <div class="flex justify-between items-center h-14 px-4 border-b border-zinc-700">
          <div class="text-base text-neutral-50 font-medium">Certificates</div>
          <div>
            <form phx-change="validate-cert" phx-drop-target={@uploads.certificate.ref} phx-target={@myself}>
              <div class="flex px-3 py-1.5 gap-2 rounded bg-zinc-800 border border-zinc-600 hover:cursor-pointer">
                <svg class="w-5 h-5" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                  <path
                    d="M6.66671 16.6667H5.00004C4.07957 16.6667 3.33337 15.9205 3.33337 15V5.00004C3.33337 4.07957 4.07957 3.33337 5.00004 3.33337H12.643C13.085 3.33337 13.509 3.50897 13.8215 3.82153L16.1786 6.17855C16.4911 6.49111 16.6667 6.91504 16.6667 7.35706V15C16.6667 15.9205 15.9205 16.6667 15 16.6667H13.3334M6.66671 16.6667V12.5H13.3334V16.6667M6.66671 16.6667H13.3334M6.66671 6.66671V9.16671H9.16671V6.66671H6.66671Z"
                    stroke="#A1A1AA"
                    stroke-width="1.2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  />
                </svg>
                <label for={@uploads.certificate.ref} class="text-sm font-medium text-zinc-300 hover:cursor-pointer">Upload certificate</label>
                <.live_file_input upload={@uploads.certificate} class="hidden" />
              </div>
            </form>
          </div>
        </div>
        <div class="py-2 px-4 flex flex-col gap-1">
          <div :if={Enum.empty?(@device.device_certificates)} class="flex items-center gap-6 h-16 p-2">
            <div>No certificates have been uploaded.</div>
          </div>
          <div :for={certificate <- @device.device_certificates} class="flex items-center gap-6 h-16 p-2">
            <div class="flex items-center h-8 py-1 px-2 bg-zinc-800 border border-zinc-700 rounded-full">
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
              <div class="text-zinc-300">Serial: {Utils.format_serial(certificate.serial)}</div>
              <div class="flex gap-2">
                <div class="text-xs text-zinc-400 tracking-wide">
                  <span>Last used:</span>
                  <%= if !is_nil(certificate.last_used) do %>
                    <span>{DateTimeFormat.from_now(certificate.last_used)}</span>
                  <% else %>
                    <span>Never</span>
                  <% end %>
                </div>

                <div class="text-xs text-zinc-400 tracking-wide">
                  <span>Not before:</span>
                  <span>{Calendar.strftime(certificate.not_before, "%Y-%m-%d")}</span>
                </div>

                <div class="text-xs text-zinc-400 tracking-wide">
                  <span>Not after:</span>
                  <span>{Calendar.strftime(certificate.not_after, "%Y-%m-%d")}</span>
                </div>
                <div class="text-xs text-zinc-400 tracking-wide">
                  <%!-- <%= Timex.from_now(entry.inserted_at) %> --%>
                </div>
                <div class="flex items-center">
                  <svg class="h-0.5 w-0.5" viewBox="0 0 2 2" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <circle cx="1" cy="1" r="1" fill="#71717A" />
                  </svg>
                </div>
                <div class="text-xs text-zinc-400 tracking-wide">
                  <%!-- <%= Calendar.strftime(entry.inserted_at, "%Y-%m-%d at %I:%M:%S %p UTC") %> --%>
                </div>
              </div>
            </div>
            <div class="flex gap-2">
              <.link
                class="flex px-3 py-1.5 gap-2 rounded bg-zinc-800 border border-zinc-600"
                href={~p"/org/#{@org.name}/#{@product.name}/devices/#{@device.identifier}/certificate/#{certificate.serial}/download"}
              >
                <svg class="w-5 h-5" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
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
                class="flex px-3 py-1.5 gap-2 rounded bg-zinc-800 border border-red-500"
                type="button"
                phx-target={@myself}
                phx-click="delete-certificate"
                phx-value-serial={certificate.serial}
                data-confirm="Are you sure you want to delete this certificate?"
              >
                <svg class="w-5 h-5" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
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

      <div :if={@device.deleted_at} class="flex flex-col w-full bg-zinc-900 border border-zinc-700 rounded">
        <div class="flex items-center p-6 gap-6 border-t border-zinc-700">
          <div>
            <button
              class="flex px-3 py-1.5 gap-2 rounded bg-zinc-800 border border-zinc-600"
              type="button"
              phx-target={@myself}
              phx-click="restore-device"
              data-confirm="Are you sure you want to restore this device?"
            >
              <svg class="size-5" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path
                  d="M8.5 18.9999H5.39903C3.87406 18.9999 2.91012 17.3617 3.65071 16.0287L7 9.99994M7 9.99994L3 11.9999M7 9.99994L8 13.9999M18.9999 13.9999L20.1987 16.0122C20.9929 17.3454 20.0323 19.0358 18.4805 19.0358L12.768 19.0358M12.768 19.0358L16 21.9999M12.768 19.0358L16 15.9999M8.5 6.99994L10.5883 3.86749C11.4401 2.58975 13.3545 2.70894 14.0413 4.08246L17 9.99994M17 9.99994L18 5.99994M17 9.99994L13 8.99994"
                  stroke="#A1A1AA"
                  stroke-width="1.2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
              </svg>

              <span class="text-sm font-medium text-zinc-300">Restore device</span>
            </button>
          </div>
          <div class="text-zinc-300">
            The device has been disabled. Attempts to connect to NervesHub will be blocked.
          </div>
        </div>
      </div>

      <div :if={@device.deleted_at} class="flex flex-col w-full bg-zinc-900 border border-zinc-700 rounded">
        <div class="flex items-center p-6 gap-6 border-t border-zinc-700">
          <div>
            <button
              class="flex px-3 py-1.5 gap-2 rounded bg-zinc-800 border border-red-500"
              type="button"
              phx-target={@myself}
              phx-click="destroy-device"
              data-confirm="Are you sure you want to permanently delete this device?"
            >
              <svg class="size-5 stroke-red-500" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path
                  d="M12.4999 5.83337H7.49992M12.4999 5.83337H14.9999M12.4999 5.83337C12.4999 4.45266 11.3806 3.33337 9.99992 3.33337C8.61921 3.33337 7.49992 4.45266 7.49992 5.83337M7.49992 5.83337H4.99992M3.33325 5.83337H4.99992M4.99992 5.83337V15C4.99992 15.9205 5.74611 16.6667 6.66659 16.6667H13.3333C14.2537 16.6667 14.9999 15.9205 14.9999 15V5.83337M14.9999 5.83337H16.6666M8.33325 9.16671V13.3334M11.6666 13.3334V9.16671"
                  stroke-width="1.2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
              </svg>

              <span class="text-sm font-medium text-red-500">Permanently delete device</span>
            </button>
          </div>
        </div>
      </div>

      <div :if={!@device.deleted_at} class="flex flex-col w-full bg-zinc-900 border border-zinc-700 rounded">
        <div class="flex items-center p-6 gap-6 border-t border-zinc-700">
          <div>
            <button
              class="flex px-3 py-1.5 gap-2 rounded bg-zinc-800 border border-red-500 hover:bg-red-100"
              type="button"
              phx-target={@myself}
              phx-click="delete-device"
              data-confirm="Are you sure you want to delete this device? This will also delete any certificates associated with the device."
            >
              <svg class="size-5 stroke-red-500" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path
                  d="M12.4999 5.83337H7.49992M12.4999 5.83337H14.9999M12.4999 5.83337C12.4999 4.45266 11.3806 3.33337 9.99992 3.33337C8.61921 3.33337 7.49992 4.45266 7.49992 5.83337M7.49992 5.83337H4.99992M3.33325 5.83337H4.99992M4.99992 5.83337V15C4.99992 15.9205 5.74611 16.6667 6.66659 16.6667H13.3333C14.2537 16.6667 14.9999 15.9205 14.9999 15V5.83337M14.9999 5.83337H16.6666M8.33325 9.16671V13.3334M11.6666 13.3334V9.16671"
                  stroke-width="1.2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
              </svg>
              <span class="text-sm font-medium text-red-500">Delete device</span>
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

  def handle_event("update-device-settings", %{"device" => device_params}, socket) do
    authorized!(:"device:update", socket.assigns.org_user)

    %{device: device, user: user} = socket.assigns

    message = "User #{user.name} updated device #{device.identifier}"

    case Devices.update_device_with_audit(device, device_params, user, message) do
      {:ok, _device} ->
        socket
        |> send_toast(:info, "Device updated.")
        |> noreply()

      {:error, :update_with_audit, changeset, _} ->
        socket
        |> send_toast(:error, "We couldn't save your changes.")
        |> assign(:settings_form, to_form(changeset))
        |> noreply()

      {:error, _, _, _} ->
        socket
        |> send_toast(:error, "An unknown error occured, please contact support.")
        |> noreply()
    end
  end

  def handle_event("delete-device", _, socket) do
    authorized!(:"device:delete", socket.assigns.org_user)

    {:ok, device} = Devices.delete_device(socket.assigns.device)

    send(self(), :reload_device)

    socket
    |> assign(:device, device)
    |> send_toast(:info, "The device has been deleted. This action can be undone.")
    |> noreply()
  end

  def handle_event("restore-device", _, socket) do
    authorized!(:"device:restore", socket.assigns.org_user)

    {:ok, device} = Devices.restore_device(socket.assigns.device)

    send(self(), :reload_device)

    socket
    |> assign(:device, device)
    |> send_toast(:info, "The device has been restored.")
    |> noreply()
  end

  def handle_event("destroy-device", _, socket) do
    %{org: org, org_user: org_user, product: product, device: device} = socket.assigns

    authorized!(:"device:destroy", org_user)

    {:ok, _device} = Devices.destroy_device(device)

    send(self(), :reload_device)

    socket
    |> send_toast(:info, "Device permanently destroyed successfully.")
    |> push_navigate(to: ~p"/org/#{org.name}/#{product.name}/devices")
    |> noreply()
  end

  # A phx-change handler is required when using live uploads.
  def handle_event("validate-cert", _, socket), do: {:noreply, socket}

  def handle_event(
        "delete-certificate",
        %{"serial" => serial},
        %{assigns: %{device: device}} = socket
      ) do
    certs = device.device_certificates

    with db_cert <- Enum.find(certs, &(&1.serial == serial)),
         {:ok, _db_cert} <- Devices.delete_device_certificate(db_cert),
         updated_certs <- Enum.reject(certs, &(&1.serial == serial)) do
      socket
      |> send_toast(:info, "Certificate deleted.")
      |> assign(device: %{device | device_certificates: updated_certs})
      |> noreply()
    else
      _ ->
        socket
        |> send_toast(:error, "Failed to delete certificate, please contact support.")
        |> noreply()
    end
  end

  def handle_event("update-extension", %{"extension" => extension} = params, socket) do
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
        send_toast(
          socket,
          :info,
          "The #{extension} extension successfully #{(value == "on" && "enabled") || "disabled"}."
        )

      {:error, _changeset} ->
        send_toast(
          socket,
          :error,
          "There was an unexpected error when updating the #{extension} extension. Please contact support."
        )
    end
    |> noreply()
  end

  def handle_progress(:certificate, %{done?: true} = entry, socket) do
    socket
    |> consume_uploaded_entry(entry, &import_cert(socket, &1.path))
    |> noreply()
  end

  def handle_progress(:certificate, _entry, socket), do: {:noreply, socket}

  defp import_cert(%{assigns: %{device: device}} = socket, path) do
    with {:ok, pem_or_der} <- File.read(path),
         {:ok, otp_cert} <- Certificate.from_pem_or_der(pem_or_der),
         {:ok, db_cert} <- Devices.create_device_certificate(device, otp_cert) do
      updated = update_in(device.device_certificates, &[db_cert | &1])

      assign(socket, :device, updated)
      |> send_toast(:info, "Certificate Upload Successful")
    else
      {:error, :malformed} ->
        send_toast(socket, :error, "Incorrect filetype or malformed certificate")

      {:error, %Ecto.Changeset{errors: errors}} ->
        formatted =
          Enum.map_join(errors, "\n", fn {field, {msg, _}} ->
            ["* ", to_string(field), " ", msg]
          end)

        send_toast(socket, :error, IO.iodata_to_binary(["Failed to save:\n", formatted]))

      err ->
        send_toast(socket, :error, "Unknown file error - #{inspect(err)}")
    end
    |> ok()
  end

  defp extensions() do
    for extension <- Extensions.list(),
        into: %{},
        do: {extension, Extensions.module(extension).description()}
  end

  defp tags_to_string(%Phoenix.HTML.FormField{} = field) do
    tags_to_string(field.value)
  end

  defp tags_to_string(%{tags: tags}), do: tags_to_string(tags)
  defp tags_to_string(tags) when is_list(tags), do: Enum.join(tags, ", ")
  defp tags_to_string(tags), do: tags
end
