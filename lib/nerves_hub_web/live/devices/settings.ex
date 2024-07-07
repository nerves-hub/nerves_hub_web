defmodule NervesHubWeb.Live.Devices.Settings do
  use NervesHubWeb, :updated_live_view

  alias NervesHubWeb.Components.Utils
  alias NervesHubWeb.LayoutView.DateTimeFormat

  alias NervesHub.Certificate
  alias NervesHub.Devices
  alias NervesHub.Repo

  def mount(%{"device_identifier" => device_identifier}, _session, socket) do
    {:ok, device} = Devices.get_device_by_identifier(socket.assigns.org, device_identifier)

    changeset = Ecto.Changeset.change(device)

    socket
    |> page_title("Device Settings #{device.identifier} - #{socket.assigns.product.name}")
    |> assign(:toggle_upload, false)
    |> assign(:device, device)
    |> assign(:form, to_form(changeset))
    |> assign(:tab_hint, :devices)
    |> allow_upload(:certificate,
      accept: :any,
      auto_upload: true,
      max_entries: 1,
      progress: &handle_progress/3
    )
    |> ok()
  end

  def handle_event("update-device", %{"device" => device_params}, socket) do
    authorized!(:"device:update", socket.assigns.org_user)

    %{org: org, product: product, device: device, user: user} = socket.assigns

    message = "#{user.name} updated device #{device.identifier}"

    case Devices.update_device_with_audit(device, device_params, user, message) do
      {:ok, _device} ->
        socket
        |> put_flash(:info, "Device updated")
        |> push_navigate(to: ~p"/org/#{org.name}/#{product.name}/devices")
        |> noreply()

      {:error, changeset} ->
        socket
        |> assign(:form, to_form(changeset))
        |> noreply()
    end
  end

  def handle_event("toggle-upload", %{"toggle" => toggle}, socket) do
    {:noreply, assign(socket, :toggle_upload, toggle != "true")}
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

  defp tags_to_string(%Phoenix.HTML.Form{} = form) do
    form.data.tags
    |> tags_to_string()
  end

  defp tags_to_string(%{tags: tags}), do: tags_to_string(tags)
  defp tags_to_string(tags) when is_list(tags), do: Enum.join(tags, ",")
  defp tags_to_string(tags), do: tags
end
