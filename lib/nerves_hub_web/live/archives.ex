defmodule NervesHubWeb.Live.Archives do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.{Accounts, Archives}

  embed_templates("archive_templates/*")

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
    |> page_title("Archives - #{product.name}")
    |> assign(:archives, Archives.all_by_product(product))
    |> assign(:org_keys, Accounts.list_org_keys(socket.assigns.org))
    |> render_with(&list_archives_template/1)
  end

  defp apply_action(%{assigns: %{product: product}} = socket, :show, %{
         "archive_uuid" => archive_uuid
       }) do
    {:ok, archive} = Archives.get(product, archive_uuid)

    socket
    |> page_title("Archive #{archive_uuid} - #{product.name}")
    |> assign(:archive, archive)
    |> assign(:org_keys, Accounts.list_org_keys(socket.assigns.org))
    |> render_with(&show_archive_template/1)
  end

  defp apply_action(%{assigns: %{product: product}} = socket, :upload, _params) do
    socket
    |> page_title("Upload Archive - #{product.name}")
    |> assign(:error_message, nil)
    |> allow_upload(:archive,
      accept: ~w(.fw),
      max_entries: 1,
      auto_upload: true,
      max_file_size: 200_000_000,
      progress: &handle_progress/3
    )
    |> render_with(&upload_archive_template/1)
  end

  @impl Phoenix.LiveView
  def handle_event("archive-selected", _, socket) do
    {:noreply, socket}
  end

  # the delete handler for the list page
  def handle_event("delete-archive", %{"archive_uuid" => uuid}, socket) do
    authorized!(:"archive:delete", socket.assigns.org_user)

    {:ok, archive} = Archives.get(socket.assigns.product, uuid)

    case Archives.delete_archive(archive) do
      {:ok, _} ->
        socket
        |> assign(:archives, Archives.all_by_product(socket.assigns.product))
        |> put_flash(:info, "Archive successfully deleted")
        |> noreply()

      {:error, changeset} ->
        error_feedback(socket, changeset)
    end
  end

  # the delete handler for the show page
  def handle_event("delete-archive", _params, socket) do
    authorized!(:"archive:delete", socket.assigns.org_user)

    %{org: org, product: product, archive: archive} = socket.assigns

    {:ok, archive} = Archives.get(socket.assigns.product, archive.uuid)

    case Archives.delete_archive(archive) do
      {:ok, _} ->
        socket
        |> put_flash(:info, "Archive successfully deleted")
        |> push_patch(to: ~p"/org/#{org.name}/#{product.name}/archives")
        |> noreply()

      {:error, changeset} ->
        error_feedback(socket, changeset)
    end
  end

  def handle_progress(:archive, entry, socket) do
    authorized!(:"archive:upload", socket.assigns.org_user)

    if entry.done? do
      [filepath] =
        consume_uploaded_entries(socket, :archive, fn %{path: path}, _entry ->
          dest = Path.join(System.tmp_dir(), Path.basename(path))
          File.cp!(path, dest)
          {:ok, dest}
        end)

      try do
        create_archive(socket, filepath)
      after
        File.rm(filepath)
      end
    else
      {:noreply, socket}
    end
  end

  defp create_archive(socket, filepath) do
    case Archives.create(socket.assigns.product, filepath) do
      {:ok, _firmware} ->
        socket
        |> put_flash(:info, "Archive uploaded")
        |> push_patch(
          to: ~p"/org/#{socket.assigns.org.name}/#{socket.assigns.product.name}/archives"
        )
        |> noreply()

      {:error, :no_public_keys} ->
        error_feedback(
          socket,
          "Please register public keys for verifying archive signatures first"
        )

      {:error, :invalid_signature} ->
        error_feedback(socket, "Archive corrupt, signature invalid, or missing public key")

      {:error, %{errors: [uuid: _]}} ->
        error_feedback(socket, "Archive UUID is not unique for the product")

      {:error, error} when is_binary(error) ->
        error_feedback(socket, error)

      _ ->
        error_feedback(
          socket,
          "Unknown error uploading archive. Please contact support if this happens again"
        )
    end
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
