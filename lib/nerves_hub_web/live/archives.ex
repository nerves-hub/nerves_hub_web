defmodule NervesHubWeb.Live.Archives do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Accounts
  alias NervesHub.Archives
  alias NervesHubWeb.Components.Pager
  alias NervesHubWeb.Components.Sorting

  embed_templates("archive_templates/*")

  @pagination_opts ["page_number", "page_size", "sort", "sort_direction"]

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

  defp apply_action(%{assigns: %{product: product}} = socket, :index, unsigned_params) do
    socket
    |> page_title("Archives - #{product.name}")
    |> sidebar_tab(:archives)
    |> assign(:archives, Archives.all_by_product(product))
    |> assign(:org_keys, Accounts.list_org_keys(socket.assigns.org))
    |> assign(:params, unsigned_params)
    |> allow_upload(:archive,
      accept: ~w(.fw),
      max_entries: 1,
      auto_upload: true,
      max_file_size: max_file_size(),
      progress: &handle_progress/3
    )
    |> assign_archives_with_pagination()
    |> render_with(&list_archives_template/1)
  end

  defp apply_action(%{assigns: %{product: product}} = socket, :show, %{"archive_uuid" => archive_uuid}) do
    archive = Archives.get_by_product_and_uuid!(product, archive_uuid)

    socket
    |> page_title("Archive #{archive_uuid} - #{product.name}")
    |> assign(:archive, archive)
    |> assign(:org_keys, Accounts.list_org_keys(socket.assigns.org))
    |> render_with(&show_archive_template/1)
  end

  # A phx-change handler is required when using live uploads.
  @impl Phoenix.LiveView
  def handle_event("validate-firmware", _, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def handle_event("paginate", %{"page" => page_num}, socket) do
    params = %{"page_number" => page_num}

    socket
    |> push_patch(to: self_path(socket, params))
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_event("set-paginate-opts", %{"page-size" => page_size}, socket) do
    params = %{"page_size" => page_size, "page_number" => 1}

    socket
    |> push_patch(to: self_path(socket, params))
    |> noreply()
  end

  # Handles event of user clicking the same field that is already sorted
  # For this case, we switch the sorting direction of same field
  @impl Phoenix.LiveView
  def handle_event("sort", %{"sort" => value}, %{assigns: %{current_sort: current_sort}} = socket)
      when value == current_sort do
    %{sort_direction: sort_direction} = socket.assigns

    # switch sort direction for column because
    sort_direction = if sort_direction == "desc", do: "asc", else: "desc"
    params = %{sort_direction: sort_direction, sort: value}

    socket
    |> push_patch(to: self_path(socket, params))
    |> noreply()
  end

  # User has clicked a new column to sort
  @impl Phoenix.LiveView
  def handle_event("sort", %{"sort" => value}, socket) do
    new_params = %{sort: value}

    socket
    |> push_patch(to: self_path(socket, new_params))
    |> noreply()
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

  def handle_event("delete-archive", _params, socket) do
    authorized!(:"archive:delete", socket.assigns.org_user)

    %{org: org, product: product, archive: archive} = socket.assigns

    {:ok, archive} = Archives.get(socket.assigns.product, archive.uuid)

    case Archives.delete_archive(archive) do
      {:ok, _} ->
        socket
        |> put_flash(:info, "Archive successfully deleted")
        |> push_patch(to: ~p"/org/#{org}/#{product}/archives")
        |> noreply()

      {:error, changeset} ->
        message =
          changeset.errors
          |> Enum.map_join(", ", fn {_field, {message, _info}} -> message end)

        error_feedback(socket, "The archive couldn't be deleted: #{message}.")
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

  defp assign_archives_with_pagination(socket) do
    %{assigns: %{product: product, params: params}} = socket

    pagination_opts = Map.take(params, @pagination_opts)

    opts = %{
      page: pagination_opts["page_number"],
      page_size: pagination_opts["page_size"],
      sort: pagination_opts["sort"] || "inserted_at",
      sort_direction: pagination_opts["sort_direction"]
    }

    {entries, pager_meta} = Archives.filter(product, opts)

    socket
    |> assign(:current_sort, opts.sort)
    |> assign(:sort_direction, opts.sort_direction)
    |> assign(:archives, entries)
    |> assign(:pager_meta, pager_meta)
  end

  defp self_path(socket, new_params) do
    current_params =
      socket.assigns.params
      |> Map.reject(fn {key, _val} -> key in ["org_name", "product_name"] end)

    params =
      stringify_keys(new_params)
      |> Enum.into(current_params)

    ~p"/org/#{socket.assigns.org}/#{socket.assigns.product}/archives?#{params}"
  end

  defp stringify_keys(params) do
    for {key, value} <- params, into: %{} do
      if is_atom(key) do
        {to_string(key), value}
      else
        {key, value}
      end
    end
  end

  defp create_archive(socket, filepath) do
    case Archives.create(socket.assigns.product, filepath) do
      {:ok, _firmware} ->
        socket
        |> put_flash(:info, "Archive uploaded successfully.")
        |> push_patch(to: ~p"/org/#{socket.assigns.org}/#{socket.assigns.product}/archives")
        |> noreply()

      {:error, :no_public_keys} ->
        error_feedback(
          socket,
          "Please register public keys for verifying archive signatures first"
        )

      {:error, :invalid_signature} ->
        error_feedback(
          socket,
          "Archive corrupt, signature invalid, or the key used for signing hasn't been uploaded."
        )

      {:error, %{errors: [uuid: _]}} ->
        error_feedback(
          socket,
          "Archive UUID is not unique for the product, please check if this archive has been previously uploaded."
        )

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
    |> put_flash(:error, message)
    |> noreply()
  end

  defp format_signed(%{org_key_id: org_key_id}, org_keys) do
    key = Enum.find(org_keys, &(&1.id == org_key_id))
    "#{key.name}"
  end

  defp format_file_size(size) do
    cond do
      size < 1_000 -> "#{size} Bytes"
      size < 1_000_000 -> "#{round(Float.round(size / 1_000))} Kilobytes"
      true -> "#{round(Float.round(size / 1_000_000))} Megabytes"
    end
  end

  defp max_file_size() do
    Application.get_env(:nerves_hub, NervesHub.Uploads, [])[:max_size]
  end
end
