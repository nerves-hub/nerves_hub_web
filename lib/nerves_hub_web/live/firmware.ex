defmodule NervesHubWeb.Live.Firmware do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.{Accounts, Firmwares}

  embed_templates("firmware_templates/*")

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    socket
    |> apply_action(socket.assigns.live_action, params)
    |> noreply()
  end

  defp apply_action(%{assigns: %{product: product}} = socket, :index, _params) do
    socket
    |> page_title("Firmware - #{product.name}")
    |> assign(:firmware, Firmwares.get_firmwares_by_product(product.id))
    |> assign(:org_keys, Accounts.list_org_keys(socket.assigns.org))
    |> render_with(&list_firmware_template/1)
  end

  defp apply_action(%{assigns: %{product: product}} = socket, :show, %{
         "firmware_uuid" => firmware_uuid
       }) do
    {:ok, firmware} = Firmwares.get_firmware_by_product_and_uuid(product, firmware_uuid)

    socket
    |> page_title("Firmware #{firmware_uuid} - #{product.name}")
    |> assign(:firmware, firmware)
    |> assign(:org_keys, Accounts.list_org_keys(socket.assigns.org))
    |> render_with(&show_firmware_template/1)
  end

  defp apply_action(%{assigns: %{product: product}} = socket, :upload, _params) do
    socket
    |> page_title("Upload Firmware - #{product.name}")
    |> assign(:error_message, nil)
    |> allow_upload(:firmware,
      accept: ~w(.fw),
      max_entries: 1,
      auto_upload: true,
      max_file_size: 200_000_000,
      progress: &handle_progress/3
    )
    |> render_with(&upload_firmware_template/1)
  end

  @impl Phoenix.LiveView
  def handle_event("firmware-selected", _, socket) do
    {:noreply, socket}
  end

  # the delete handler for the list page
  def handle_event("delete-firmware", %{"firmware_uuid" => uuid}, socket) do
    {:ok, firmware} = Firmwares.get_firmware_by_product_and_uuid(socket.assigns.product, uuid)

    case Firmwares.delete_firmware(firmware) do
      {:ok, _} ->
        socket
        |> assign(:firmware, Firmwares.get_firmwares_by_product(socket.assigns.product.id))
        |> put_flash(:info, "Firmware successfully deleted")
        |> noreply()

      {:error, changeset} ->
        error_feedback(socket, changeset)
    end
  end

  # the delete handler for the show page
  def handle_event("delete-firmware", _params, socket) do
    %{org: org, product: product, firmware: firmware} = socket.assigns

    {:ok, firmware} = Firmwares.get_firmware_by_product_and_uuid(product, firmware.uuid)

    case Firmwares.delete_firmware(firmware) do
      {:ok, _} ->
        socket
        |> put_flash(:info, "Firmware successfully deleted")
        |> push_patch(to: ~p"/org/#{org.name}/#{product.name}/firmware")
        |> noreply()

      {:error, changeset} ->
        error_feedback(socket, changeset)
    end
  end

  def handle_progress(:firmware, entry, socket) do
    if entry.done? do
      [filepath] =
        consume_uploaded_entries(socket, :firmware, fn %{path: path}, _entry ->
          dest = Path.join(System.tmp_dir(), Path.basename(path))
          File.cp!(path, dest)
          {:ok, dest}
        end)

      try do
        create_firmware(socket, filepath)
      after
        File.rm(filepath)
      end
    else
      {:noreply, assign(socket, status: "uploading...")}
    end
  end

  defp create_firmware(socket, filepath) do
    case Firmwares.create_firmware(socket.assigns.org, filepath) do
      {:ok, _firmware} ->
        socket
        |> put_flash(:info, "Firmware uploaded")
        |> push_patch(
          to: ~p"/org/#{socket.assigns.org.name}/#{socket.assigns.product.name}/firmware"
        )
        |> noreply()

      {:error, :no_public_keys} ->
        error_feedback(
          socket,
          "Please register public keys for verifying firmware signatures first"
        )

      {:error, :invalid_signature} ->
        error_feedback(socket, "Firmware corrupt, signature invalid, or missing public key")

      {:error,
       %Ecto.Changeset{
         errors: [product_id: {"can't be blank", [validation: :required]}]
       }} ->
        error_feedback(socket, "No matching product could be found.")

      {:error, %Ecto.Changeset{}} ->
        error_feedback(socket, "Unknown error uploading firmware.")

      {:error, error} when is_binary(error) ->
        error_feedback(socket, error)

      _ ->
        error_feedback(socket, "Unknown error uploading firmware")
    end
  end

  defp error_feedback(socket, %Ecto.Changeset{} = changeset) do
    error_message =
      changeset.errors
      |> Enum.map(fn {_field, {message, _info}} -> message end)
      |> Enum.join(", ")

    socket
    |> put_flash(:error, error_message)
    |> noreply()
  end

  defp error_feedback(socket, message) do
    socket
    |> assign(:error_message, message)
    |> noreply()
  end

  defp format_signed(%{org_key_id: org_key_id}, org_keys) do
    key = Enum.find(org_keys, &(&1.id == org_key_id))
    "#{key.name}"
  end
end
