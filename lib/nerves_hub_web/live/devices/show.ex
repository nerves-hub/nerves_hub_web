defmodule NervesHubWeb.Live.Devices.Show do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.AuditLogs
  alias NervesHub.Certificate
  alias NervesHub.Deployments
  alias NervesHub.Devices
  alias NervesHub.Devices.UpdatePayload
  alias NervesHub.Firmwares
  alias NervesHub.Repo
  alias NervesHub.Tracker

  alias Phoenix.Socket.Broadcast

  alias NervesHubWeb.Components.Utils
  alias NervesHubWeb.LayoutView.DateTimeFormat
  import NervesHubWeb.DeviceView, only: [connecting_code: 1]

  on_mount NervesHubWeb.Mounts.FetchDevice

  def mount(_params, _session, socket) do
    device = socket.assigns.device

    if connected?(socket) do
      socket.endpoint.subscribe("device:#{device.identifier}:internal")
    end

    socket
    |> page_title("Device - #{device.identifier}")
    |> assign(:status, Tracker.status(device))
    |> assign(:deployment, device.deployment)
    |> assign(:toggle_upload, false)
    |> assign(:results, [])
    |> assign(:deployments, Deployments.alternate_deployments(device))
    |> assign(:firmwares, Firmwares.get_firmware_for_device(device))
    |> allow_upload(:certificate,
      accept: :any,
      auto_upload: true,
      max_entries: 1,
      progress: &handle_progress/3
    )
    |> audit_log_assigns(1)
    |> ok()
  end

  def handle_progress(:certificate, %{done?: true} = entry, socket) do
    socket =
      socket
      |> clear_flash(:info)
      |> clear_flash(:error)
      |> consume_uploaded_entry(entry, &import_cert(socket, &1.path))

    {:noreply, socket}
  end

  def handle_progress(:certificate, _entry, socket), do: {:noreply, socket}

  defp import_cert(%{assigns: %{device: device}} = socket, path) do
    socket =
      with {:ok, pem_or_der} <- File.read(path),
           {:ok, otp_cert} <- Certificate.from_pem_or_der(pem_or_der),
           {:ok, db_cert} <- Devices.create_device_certificate(device, otp_cert) do
        updated = update_in(device.device_certificates, &[db_cert | &1])

        assign(socket, :device, updated)
        |> put_flash(:info, "Certificate Upload Successful")
      else
        {:error, :malformed} ->
          put_flash(socket, :error, "Incorrect filetype or malformed certificate")

        {:error, %Ecto.Changeset{errors: errors}} ->
          formatted =
            Enum.map_join(errors, "\n", fn {field, {msg, _}} ->
              ["* ", to_string(field), " ", msg]
            end)

          put_flash(socket, :error, IO.iodata_to_binary(["Failed to save:\n", formatted]))

        err ->
          put_flash(socket, :error, "Unknown file error - #{inspect(err)}")
      end

    {:ok, socket}
  end

  def handle_info(%Broadcast{event: "connection_change", payload: payload}, socket) do
      socket
      |> assign(:status, payload.status)
      |> assign(:fwup_progress, nil)
      |> noreply()
  end

  def handle_info(%Broadcast{event: "fwup_progress", payload: payload}, socket) do
    {:noreply, assign(socket, :fwup_progress, payload.percent)}
  end

  # Ignore unknown messages
  def handle_info(_unknown, socket), do: {:noreply, socket}

  def handle_event("reboot", _value, %{assigns: %{device: device, user: user}} = socket) do
    authorized!(:reboot_device, socket.assigns.org_user)

    AuditLogs.audit!(user, device, "#{user.name} rebooted device #{device.identifier}")

    socket.endpoint.broadcast_from(self(), "device:#{socket.assigns.device.id}", "reboot", %{})

    {:noreply, put_flash(socket, :info, "Device Reboot Requested")}
  end

  def handle_event("reconnect", _value, %{assigns: %{device: device}} = socket) do
    authorized!(:reconnect_device, socket.assigns.org_user)
    socket.endpoint.broadcast("device_socket:#{device.id}", "disconnect", %{})
    {:noreply, socket}
  end

  def handle_event("identify", _value, socket) do
    authorized!(:identify_device, socket.assigns.org_user)
    socket.endpoint.broadcast_from(self(), "device:#{socket.assigns.device.id}", "identify", %{})
    {:noreply, socket}
  end

  def handle_event("paginate", %{"page" => page_num}, socket) do
    {:noreply, socket |> audit_log_assigns(String.to_integer(page_num))}
  end

  def handle_event("clear-penalty-box", _params, socket) do
    authorized!(:clear_penalty_box_device, socket.assigns.org_user)

    %{device: device, user: user} = socket.assigns

    case Devices.clear_penalty_box(device, user) do
      {:ok, updated_device} ->
        {:noreply, assign(socket, :device, Repo.preload(updated_device, [:device_certificates]))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to mark health state")}
    end
  end

  def handle_event(
        "toggle_health_state",
        _params,
        %{assigns: %{device: device, user: user}} = socket
      ) do
    authorized!(:toggle_updates_device, socket.assigns.org_user)

    case Devices.toggle_health(device, user) do
      {:ok, updated_device} ->
        {:noreply, assign(socket, :device, Repo.preload(updated_device, [:device_certificates]))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to mark health state")}
    end
  end

  def handle_event(
        "delete-certificate",
        %{"serial" => serial},
        %{assigns: %{device: device}} = socket
      ) do
    certs = device.device_certificates

    with db_cert <- Enum.find(certs, &(&1.serial == serial)),
         {:ok, _db_cert} <- Devices.delete_device_certificate(db_cert),
         updated_certs = Enum.reject(certs, &(&1.serial == serial)) do
      {:noreply, assign(socket, device: %{device | device_certificates: updated_certs})}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Failed to delete certificate #{serial}")}
    end
  end

  def handle_event("restore", _, socket) do
    authorized!(:restore_device, socket.assigns.org_user)

    case Devices.restore_device(socket.assigns.device) do
      {:ok, device} ->
        {:noreply, assign(socket, device: device)}

      _ ->
        {:noreply, put_flash(socket, :error, "Failed to restore device")}
    end
  end

  def handle_event("destroy", _, socket) do
    authorized!(:destroy_device, socket.assigns.org_user)

    case Repo.destroy(socket.assigns.device) do
      {:ok, _device} ->
        path = ~p"/org/#{socket.assigns.org.name}/#{socket.assigns.product.name}/devices"

        {:noreply, redirect(socket, to: path)}

      _ ->
        {:noreply, put_flash(socket, :error, "Failed to destroy device")}
    end
  end

  def handle_event("delete", _, socket) do
    authorized!(:delete_device, socket.assigns.org_user)

    case Devices.delete_device(socket.assigns.device) do
      {:ok, %{device: device}} ->
        {:noreply, assign(socket, device: device)}

      _ ->
        {:noreply, put_flash(socket, :error, "Failed to delete device")}
    end
  end

  def handle_event("toggle-upload", %{"toggle" => toggle}, socket) do
    {:noreply, assign(socket, :toggle_upload, toggle != "true")}
  end

  def handle_event("clear-flash-" <> key_str, _, socket) do
    {:noreply, clear_flash(socket, String.to_existing_atom(key_str))}
  end

  def handle_event("validate-cert", _, socket), do: {:noreply, socket}

  def handle_event("push-update", %{"uuid" => uuid}, socket) do
    authorized!(:push_update_device, socket.assigns.org_user)

    product = socket.assigns.product
    {:ok, firmware} = Firmwares.get_firmware_by_product_and_uuid(product, uuid)

    {:ok, url} = Firmwares.get_firmware_url(firmware)
    {:ok, meta} = Firmwares.metadata_from_firmware(firmware)

    %{device: device, user: user} = socket.assigns

    {:ok, device} = Devices.disable_updates(device, user)
    socket = assign(socket, :device, Repo.preload(device, [:device_certificates]))

    description =
      "user #{user.username} pushed firmware #{firmware.version} #{firmware.uuid} to device #{device.identifier}"

    AuditLogs.audit!(user, device, description)

    payload = %UpdatePayload{
      update_available: true,
      firmware_url: url,
      firmware_meta: meta
    }

    NervesHubWeb.Endpoint.broadcast(
      "device:#{socket.assigns.device.id}",
      "deployments/update",
      payload
    )

    {:noreply, put_flash(socket, :info, "Pushing update")}
  end

  defp audit_log_assigns(%{assigns: %{device: device}} = socket, page_number) do
    logs = AuditLogs.logs_for_feed(device, %{page: page_number, page_size: 10})

    socket
    |> assign(:audit_logs, logs)
    |> assign(:resource_id, device.id)
  end
end
