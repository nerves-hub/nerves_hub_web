defmodule NervesHubWeb.DeviceLive.Show do
  use NervesHubWeb, :live_view

  alias NervesHubDevice.Presence

  alias NervesHub.Accounts
  alias NervesHub.AuditLogs
  alias NervesHub.Certificate
  alias NervesHub.Deployments
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.UpdatePayload
  alias NervesHub.Firmwares
  alias NervesHub.Repo
  alias NervesHub.Products

  alias Phoenix.Socket.Broadcast

  def render(assigns) do
    NervesHubWeb.DeviceView.render("show.html", assigns)
  end

  def mount(
        _params,
        %{
          "auth_user_id" => user_id,
          "org_id" => org_id,
          "product_id" => product_id,
          "device_id" => device_id
        },
        socket
      ) do
    socket =
      socket
      |> assign_new(:user, fn -> Accounts.get_user!(user_id) end)
      |> assign_new(:org, fn -> Accounts.get_org!(org_id) end)
      |> assign_new(:product, fn -> Products.get_product!(product_id) end)
      |> assign_new(:device, fn ->
        Devices.get_device_by_product(device_id, product_id, org_id)
      end)

    if connected?(socket) do
      socket.endpoint.subscribe("device:#{socket.assigns.device.id}:internal")
    end

    socket =
      socket
      |> assign(:device, sync_device(socket.assigns.device))
      |> assign(:page_title, socket.assigns.device.identifier)
      |> assign(:toggle_upload, false)
      |> assign(:results, [])
      |> assign(:deployments, Deployments.potential_deployments(socket.assigns.device))
      |> assign(:firmwares, Firmwares.get_firmware_for_device(socket.assigns.device))
      |> allow_upload(:certificate,
        accept: :any,
        auto_upload: true,
        max_entries: 1,
        progress: &handle_progress/3
      )
      |> audit_log_assigns(1)

    {:ok, socket}
  rescue
    e ->
      socket_error(socket, live_view_error(e))
  end

  # Catch-all to handle when LV sessions change.
  # Typically this is after a deploy when the
  # session structure in the module has changed
  # for mount/3
  def mount(_, _, socket) do
    socket_error(socket, live_view_error(:update))
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
  end

  def handle_info(%Broadcast{event: "connection_change", payload: payload}, socket) do
    {:noreply, assign(socket, :device, sync_device(socket.assigns.device, payload))}
  end

  # Ignore unknown messages
  def handle_info(_unknown, socket), do: {:noreply, socket}

  def handle_event("reboot", _value, %{assigns: %{device: device, user: user}} = socket) do
    user = Repo.preload(user, :org_users)

    case Enum.find(user.org_users, &(&1.org_id == device.org_id)) do
      %{role: :admin} -> do_reboot(socket, :allowed)
      _ -> do_reboot(socket, :blocked)
    end
  end

  def handle_event("paginate", %{"page" => page_num}, socket) do
    {:noreply, socket |> audit_log_assigns(String.to_integer(page_num))}
  end

  def handle_event("clear-penalty-box", _params, socket) do
    %{device: device, user: user} = socket.assigns

    socket =
      case Devices.clear_penalty_box(device, user) do
        {:ok, updated_device} ->
          meta = Map.take(device, Presence.__fields__())
          assign(socket, :device, Map.merge(updated_device, meta))

        {:error, _changeset} ->
          put_flash(socket, :error, "Failed to mark health state")
      end

    {:noreply, socket}
  end

  def handle_event(
        "toggle_health_state",
        _params,
        %{assigns: %{device: device, user: user}} = socket
      ) do
    socket =
      case Devices.toggle_health(device, user) do
        {:ok, updated_device} ->
          meta = Map.take(device, Presence.__fields__())
          assign(socket, :device, Map.merge(updated_device, meta))

        {:error, _changeset} ->
          put_flash(socket, :error, "Failed to mark health state")
      end

    {:noreply, socket}
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
    case Devices.restore_device(socket.assigns.device) do
      {:ok, device} ->
        {:noreply, assign(socket, device: device)}

      _ ->
        {:noreply, put_flash(socket, :error, "Failed to restore device")}
    end
  end

  def handle_event("destroy", _, socket) do
    case Repo.destroy(socket.assigns.device) do
      {:ok, _device} ->
        path =
          Routes.device_path(socket, :index, socket.assigns.org.name, socket.assigns.product.name)

        {:noreply, redirect(socket, to: path)}

      _ ->
        {:noreply, put_flash(socket, :error, "Failed to destroy device")}
    end
  end

  def handle_event("delete", _, socket) do
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
    firmware = Firmwares.get_firmware_by_uuid(uuid)

    {:ok, url} = Firmwares.get_firmware_url(firmware)
    {:ok, meta} = Firmwares.metadata_from_firmware(firmware)

    %{device: device, user: user} = socket.assigns

    {:ok, device} = Devices.disable_updates(device, user)
    socket = assign(socket, :device, device)

    description = "user #{user.username} pushed firmware #{firmware.version} #{firmware.uuid} to device #{device.identifier}"
    AuditLogs.audit!(user, device, :update, description, %{firmware_uuid: firmware.uuid})

    payload = %UpdatePayload{
      update_available: true,
      firmware_url: url,
      firmware_meta: meta
    }

    NervesHubWeb.Endpoint.broadcast("device:#{socket.assigns.device.id}", "update", payload)

    {:noreply, put_flash(socket, :info, "Pushing update")}
  end

  defp audit_log_assigns(%{assigns: %{device: device}} = socket, page_number) do
    logs = AuditLogs.logs_for_feed(device, %{page: page_number, page_size: 5})

    socket
    |> assign(:audit_logs, logs)
    |> assign(:resource_id, device.id)
  end

  defp do_reboot(%{assigns: %{device: device, user: user}} = socket, :allowed) do
    AuditLogs.audit!(
      user,
      device,
      :update,
      "user #{user.username} rebooted device #{device.identifier}",
      %{reboot: true}
    )

    socket.endpoint.broadcast_from(self(), "device:#{socket.assigns.device.id}", "reboot", %{})

    socket =
      socket
      |> put_flash(:info, "Device Reboot Requested")
      |> assign(:device, %{socket.assigns.device | status: "reboot-requested"})

    {:noreply, socket}
  end

  defp do_reboot(%{assigns: %{device: device, user: user}} = socket, :blocked) do
    msg = "User not authorized to reboot this device"

    AuditLogs.audit!(
      user,
      device,
      :update,
      "user #{user.username} attempted to reboot device #{device.identifier}",
      %{
        reboot: false,
        message: msg
      }
    )

    socket =
      socket
      |> put_flash(:error, msg)
      |> assign(:device, %{socket.assigns.device | status: "reboot-blocked"})

    {:noreply, socket}
  end

  def sync_device(%Device{} = device) do
    metadata = Presence.find(device)
    sync_device(device, metadata)
  end

  defp sync_device(%Device{} = device, metadata) do
    device = Repo.preload(device, :device_certificates, force: true)

    case is_nil(metadata) do
      false ->
        updates =
          Map.take(metadata, [
            :console_available,
            :firmware_metadata,
            :fwup_progress,
            :last_communication,
            :status
          ])

        Map.merge(device, updates)

      true ->
        device
    end
  end
end
