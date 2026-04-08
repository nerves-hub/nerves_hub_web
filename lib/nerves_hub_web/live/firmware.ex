defmodule NervesHubWeb.Live.Firmware do
  use NervesHubWeb, :live_view

  alias NervesHub.Accounts
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Upload
  alias NervesHubWeb.Components.Pager
  alias NervesHubWeb.Components.Sorting
  alias Phoenix.Socket.Broadcast

  embed_templates("firmware_templates/*")

  @pagination_opts ["page_number", "page_size", "sort", "sort_direction"]

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    if connected?(socket) do
      Logger.metadata(user_id: scope.user.id, product_id: scope.product.id)

      :ok = socket.endpoint.subscribe("product:#{scope.product.id}")
    end

    socket
    |> assign(:product, scope.product)
    |> ok()
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
    |> assign(:org_keys, Accounts.list_org_keys(socket.assigns.current_scope))
    |> assign(:params, unsigned_params)
    |> allow_upload(:firmware,
      accept: ~w(.fw),
      max_entries: 1,
      auto_upload: true,
      max_file_size: max_file_size(),
      progress: &handle_progress/3
    )
    |> assign_firmware_with_pagination()
    |> render_with(&list_firmware_template/1)
  end

  defp apply_action(%{assigns: %{current_scope: scope, product: product}} = socket, :show, %{
         "firmware_uuid" => firmware_uuid
       }) do
    firmware = Firmwares.get_firmware_by_uuid!(scope, firmware_uuid)

    socket
    |> page_title("Firmware #{firmware_uuid} - #{product.name}")
    |> sidebar_tab(:firmware)
    |> assign(:firmware, firmware)
    |> assign(:org_keys, Accounts.list_org_keys(scope))
    |> render_with(&show_firmware_template/1)
  end

  # A phx-change handler is required when using live uploads.
  @impl Phoenix.LiveView
  def handle_event("validate-firmware", _, socket), do: {:noreply, socket}

  def handle_event("paginate", %{"page" => page_num}, socket) do
    params = %{"page_number" => page_num}

    socket
    |> push_patch(to: self_path(socket, params))
    |> noreply()
  end

  def handle_event("set-paginate-opts", %{"page-size" => page_size}, socket) do
    params = %{"page_size" => page_size, "page_number" => 1}

    socket
    |> push_patch(to: self_path(socket, params))
    |> noreply()
  end

  # Handles event of user clicking the same field that is already sorted
  # For this case, we switch the sorting direction of same field
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
  def handle_event("sort", %{"sort" => value}, socket) do
    new_params = %{sort: value}

    socket
    |> push_patch(to: self_path(socket, new_params))
    |> noreply()
  end

  def handle_event("firmware-selected", _, socket) do
    {:noreply, socket}
  end

  # the delete handler for the list page
  def handle_event("delete-firmware", %{"firmware_uuid" => uuid}, socket) do
    authorized!(:"firmware:delete", socket.assigns.current_scope)

    {:ok, firmware} = Firmwares.get_firmware_by_uuid(socket.assigns.current_scope, uuid)

    case Firmwares.delete_firmware(firmware) do
      {:ok, _} ->
        socket
        |> assign(:firmware, Firmwares.get_firmwares_by_product(socket.assigns.product.id))
        |> put_flash(:info, "Firmware successfully deleted")
        |> noreply()

      {:error, %Ecto.Changeset{} = changeset} ->
        error_feedback(socket, changeset)
        |> noreply()
    end
  end

  # the delete handler for the show page
  def handle_event("delete-firmware", _params, socket) do
    authorized!(:"firmware:delete", socket.assigns.current_scope)

    %{current_scope: scope, firmware: firmware} = socket.assigns

    {:ok, firmware} = Firmwares.get_firmware_by_uuid(scope, firmware.uuid)

    case Firmwares.delete_firmware(firmware) do
      {:ok, _} ->
        socket
        |> put_flash(:info, "Firmware successfully deleted")
        |> push_patch(to: ~p"/org/#{scope.org}/#{scope.product}/firmware")
        |> noreply()

      {:error, changeset} ->
        error_feedback(socket, changeset, prefix: "Error deleting firmware:")
        |> noreply()
    end
  end

  @impl Phoenix.LiveView
  def handle_info(
        %Broadcast{topic: "product:" <> _product_id, event: "firmware/created", payload: %{firmware: firmware}},
        %{assigns: assigns} = socket
      )
      when assigns.live_action == :index do
    if viewing_first_page?(assigns) do
      socket
      |> assign_firmware_with_pagination()
      |> put_flash(
        :notice,
        "New firmware (#{firmware.version} - #{String.slice(firmware.uuid, 0..7)}) available for selection."
      )
      |> noreply()
    else
      socket
      |> put_flash(
        :notice,
        "New firmware (#{firmware.version} - #{String.slice(firmware.uuid, 0..7)}) available for selection. Please go back to page 1 to view it."
      )
      |> noreply()
    end
  end

  def handle_info(
        %Broadcast{topic: "product:" <> _product_id, event: "firmware/deleted", payload: %{firmware: firmware}},
        socket
      )
      when socket.assigns.live_action == :index do
    socket
    |> assign_firmware_with_pagination()
    |> put_flash(
      :notice,
      "Firmware #{firmware.version} (#{String.slice(firmware.uuid, 0..7)}) has been deleted by another user."
    )
    |> noreply()
  end

  # Ignore all other broadcasts
  def handle_info(_broadcast, socket) do
    {:noreply, socket}
  end

  def handle_progress(:firmware, entry, socket) do
    authorized!(:"firmware:upload", socket.assigns.current_scope)

    if entry.done? do
      [filepath] =
        consume_uploaded_entries(socket, :firmware, fn %{path: path}, _entry ->
          {:ok, dest} = Briefly.create()
          File.copy!(path, dest)
          {:ok, dest}
        end)

      socket
      |> create_firmware(filepath)
      |> noreply()
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

    ~p"/org/#{socket.assigns.current_scope.org}/#{socket.assigns.product}/firmware?#{params}"
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

  defp viewing_first_page?(assigns) do
    case get_in(assigns, [:params, "page_number"]) do
      nil -> true
      page_number -> String.to_integer(page_number) == 1
    end
  end

  defp create_firmware(socket, filepath) do
    case Firmwares.create_firmware(socket.assigns.current_scope.org, filepath) do
      {:ok, _firmware} ->
        socket
        |> put_flash(:info, "Firmware uploaded successfully")
        |> push_patch(to: ~p"/org/#{socket.assigns.current_scope.org}/#{socket.assigns.product}/firmware")

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
        error_feedback(
          socket,
          "No matching product could be found. Please check that your Nerves application product name (`:app` or `:name` in `mix.exs`) matches your #{Application.get_env(:nerves_hub, :web_title_suffix)} product name."
        )

      {:error,
       %Ecto.Changeset{
         errors: [
           uuid: {"has already been taken", [constraint: :unique, constraint_name: "firmwares_product_id_uuid_index"]}
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

    put_flash(socket, :error, error_message)
  end

  defp error_feedback(socket, message, _opts) do
    put_flash(socket, :error, message)
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
    Application.get_env(:nerves_hub, Upload, [])[:max_size]
  end
end
