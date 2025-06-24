defmodule NervesHubWeb.Live.Firmware do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Accounts
  alias NervesHub.Firmwares

  alias NervesHubWeb.Components.Pager
  alias NervesHubWeb.Components.Sorting

  embed_templates("firmware_templates/*")

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
    |> page_title("Firmware - #{product.name}")
    |> sidebar_tab(:firmware)
    |> assign(:org_keys, Accounts.list_org_keys(socket.assigns.org))
    |> assign(:params, unsigned_params)
    |> allow_upload(:firmware,
      accept: ~w(.fw),
      max_entries: 1,
      auto_upload: true,
      max_file_size: max_file_size(),
      progress: &handle_progress/3
    )
    |> assign_firmware_with_pagination()
    |> then(fn socket ->
      if Application.get_env(:nerves_hub, :new_ui) && socket.assigns[:new_ui] do
        render_with(socket, &list_firmware_template_new/1)
      else
        render_with(socket, &list_firmware_template/1)
      end
    end)
  end

  defp apply_action(%{assigns: %{product: product}} = socket, :show, %{
         "firmware_uuid" => firmware_uuid
       }) do
    firmware = Firmwares.get_firmware_by_product_and_uuid!(product, firmware_uuid)
    source_deltas = Firmwares.get_deltas_by_source_firmware(firmware)
    target_deltas = Firmwares.get_deltas_by_target_firmware(firmware)

    socket
    |> page_title("Firmware #{firmware_uuid} - #{product.name}")
    |> assign(:firmware, firmware)
    |> assign(:org_keys, Accounts.list_org_keys(socket.assigns.org))
    |> assign(:source_deltas, source_deltas)
    |> assign(:target_deltas, target_deltas)
    |> then(fn socket ->
      if Application.get_env(:nerves_hub, :new_ui) && socket.assigns[:new_ui] do
        render_with(socket, &show_firmware_template_new/1)
      else
        render_with(socket, &show_firmware_template/1)
      end
    end)
  end

  defp apply_action(%{assigns: %{product: product}} = socket, :upload, _params) do
    socket
    |> page_title("Upload Firmware - #{product.name}")
    |> assign(:error_message, nil)
    |> assign(:error_code, nil)
    |> allow_upload(:firmware,
      accept: ~w(.fw),
      max_entries: 1,
      auto_upload: true,
      max_file_size: max_file_size(),
      progress: &handle_progress/3
    )
    |> render_with(&upload_firmware_template/1)
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
    sort_direction = if sort_direction == "asc", do: "desc", else: "asc"

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
  def handle_event("firmware-selected", _, socket) do
    {:noreply, socket}
  end

  # the delete handler for the list page
  @impl Phoenix.LiveView
  def handle_event("delete-firmware", %{"firmware_uuid" => uuid}, socket) do
    authorized!(:"firmware:delete", socket.assigns.org_user)

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
  @impl Phoenix.LiveView
  def handle_event("delete-firmware", _params, socket) do
    authorized!(:"firmware:delete", socket.assigns.org_user)

    %{org: org, product: product, firmware: firmware} = socket.assigns

    {:ok, firmware} = Firmwares.get_firmware_by_product_and_uuid(product, firmware.uuid)

    case Firmwares.delete_firmware(firmware) do
      {:ok, _} ->
        socket
        |> put_flash(:info, "Firmware successfully deleted")
        |> push_patch(to: ~p"/org/#{org}/#{product}/firmware")
        |> noreply()

      {:error, changeset} ->
        error_feedback(socket, changeset, prefix: "Error deleting firmware:")
    end
  end

  def handle_progress(:firmware, entry, socket) do
    authorized!(:"firmware:upload", socket.assigns.org_user)

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

  defp assign_firmware_with_pagination(socket) do
    %{assigns: %{product: product, params: params}} = socket

    pagination_opts = Map.take(params, @pagination_opts)

    opts = %{
      page: pagination_opts["page_number"],
      page_size: pagination_opts["page_size"],
      sort: pagination_opts["sort"] || "inserted_at",
      sort_direction: pagination_opts["sort_direction"]
    }

    {entries, pager_meta} = Firmwares.filter(product, opts)

    socket
    |> assign(:current_sort, opts.sort)
    |> assign(:sort_direction, opts.sort_direction)
    |> assign(:firmware, entries)
    |> assign(:pager_meta, pager_meta)
  end

  defp self_path(socket, new_params) do
    current_params =
      socket.assigns.params
      |> Map.reject(fn {key, _val} -> key in ["org_name", "product_name"] end)

    params =
      stringify_keys(new_params)
      |> Enum.into(current_params)

    ~p"/org/#{socket.assigns.org}/#{socket.assigns.product}/firmware?#{params}"
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

  defp create_firmware(socket, filepath) do
    case Firmwares.create_firmware(socket.assigns.org, filepath) do
      {:ok, _firmware} ->
        socket
        |> put_flash(:info, "Firmware uploaded successfully")
        |> push_patch(to: ~p"/org/#{socket.assigns.org}/#{socket.assigns.product}/firmware")
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

      {:error,
       %Ecto.Changeset{
         errors: [
           uuid:
             {"has already been taken",
              [constraint: :unique, constraint_name: "firmwares_product_id_uuid_index"]}
         ]
       } = _changeset} ->
        error_feedback(
          socket,
          "Firmware UUID has already been taken, has this version been uploaded already?"
        )

      {:error, error} when is_binary(error) ->
        error_feedback(socket, error)

      _ ->
        error_feedback(socket, "Unknown error uploading firmware. Please contact support.")
    end
  end

  defp error_feedback(socket, changeset_or_message, opts \\ [])

  defp error_feedback(socket, %Ecto.Changeset{} = changeset, opts) do
    error_message =
      changeset.errors
      |> Enum.map_join(", ", fn {_field, {message, _info}} -> message end)

    error_message = Enum.join([opts[:prefix] || "", error_message], " ")

    socket
    |> put_flash(:error, error_message)
    |> noreply()
  end

  defp error_feedback(socket, message, _opts) do
    socket
    |> put_flash(:error, message)
    |> noreply()
  end

  defp format_file_size(size) do
    cond do
      size < 1_000 -> "#{size} Bytes"
      size < 1_000_000 -> "#{round(Float.round(size / 1_000))} Kilobytes"
      true -> "#{round(Float.round(size / 1_000_000))} Megabytes"
    end
  end

  defp format_signed(%{org_key_id: org_key_id}, org_keys) do
    key = Enum.find(org_keys, &(&1.id == org_key_id))
    "#{key.name}"
  end

  defp max_file_size() do
    Application.get_env(:nerves_hub, NervesHub.Firmwares.Upload, [])[:max_size]
  end
end
