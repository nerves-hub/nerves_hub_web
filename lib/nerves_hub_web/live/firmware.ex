defmodule NervesHubWeb.Live.Firmware do
  use NervesHubWeb, :live_view

  alias NervesHub.Accounts
  alias NervesHub.AuditLogs.ProductTemplates
  alias NervesHub.Devices
  alias NervesHub.Devices.UpdateHistory
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.UpdateTool
  alias NervesHub.Firmwares.Upload
  alias NervesHub.Products
  alias NervesHubWeb.Helpers.FirmwareDeletion
  alias NervesHubWeb.Mounts.RequireEveryDevice
  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.Socket.Broadcast

  require Logger

  on_mount(RequireEveryDevice)

  embed_templates("firmware_templates/*")

  # The tabs a `tab` param can name. Anything else, or none, is all of the
  # firmware that isn't deleted.
  @tabs %{"in_use" => :in_use, "not_in_use" => :not_in_use, "deleted" => :deleted}

  @impl Phoenix.LiveView
  @decorate requires_membership()
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    if connected?(socket) do
      Logger.metadata(user_id: scope.user.id, product_id: scope.product.id)

      :ok = Products.PubSub.subscribe(scope.product.id)
    end

    socket
    |> assign(:product, scope.product)
    |> assign(:upload_failures, [])
    |> assign(:new_firmware_uuid, nil)
    |> assign(:deleting, nil)
    |> ok()
  end

  @impl Phoenix.LiveView
  @decorate requires_membership()
  def handle_params(params, _url, socket) do
    socket
    |> apply_action(socket.assigns.live_action, params)
    |> noreply()
  end

  defp apply_action(%{assigns: %{product: product}} = socket, :index, unsigned_params) do
    socket
    |> page_title("Firmware - #{product.name}")
    |> sidebar_tab(:firmware)
    |> assign(:params, unsigned_params)
    |> allow_firmware_upload()
    |> assign_firmware_list()
    |> render_with(&list_firmware_template/1)
  end

  defp apply_action(%{assigns: %{current_scope: scope, product: product}} = socket, :show, %{
         "firmware_uuid" => firmware_uuid
       }) do
    firmware =
      scope
      |> Firmwares.get_firmware_by_uuid!(firmware_uuid, include_deleted: true)
      |> Firmwares.preload_deleted_by()

    socket
    |> page_title("Firmware #{firmware.version} (#{short_uuid(firmware.uuid)}) - #{product.name}")
    |> sidebar_tab(:firmware)
    |> assign(:org_keys, Accounts.list_org_keys(scope))
    |> assign_firmware_page(firmware)
    |> render_with(&show_firmware_template/1)
  end

  # Everything the firmware's page shows besides the firmware itself: where it
  # runs, which groups release it, its deltas and its other builds. Reloaded
  # after anything on the page changes the firmware or its deltas.
  defp assign_firmware_page(socket, firmware) do
    %{product: product} = socket.assigns

    releases = product |> Firmwares.used_by([firmware.id]) |> Map.get(firmware.id, [])
    progress = Firmwares.release_progress(firmware, Enum.map(releases, & &1.deployment_group.id))

    socket
    |> assign(:firmware, firmware)
    |> assign_deletion_state(firmware)
    |> assign(:usage, Firmwares.usage(firmware))
    |> assign(:releases, Enum.map(releases, &Map.put(&1, :progress, progress[&1.deployment_group.id])))
    |> assign(:deltas, Firmwares.get_deltas_by_target_firmware(firmware))
    |> assign(:other_builds, Firmwares.other_builds(firmware))
    |> assign_failed_installs(firmware)
  end

  # Failed installs live in ClickHouse, which can be slow or switched off, so
  # the rest of the page doesn't wait for them.
  defp assign_failed_installs(socket, firmware) do
    if analytics_enabled?() do
      %{current_scope: scope} = socket.assigns
      since = DateTime.add(DateTime.utc_now(), -7, :day)

      assign_async(socket, :failed_installs, fn ->
        {:ok,
         %{failed_installs: UpdateHistory.failed_attempts_count(scope.org.id, scope.product.id, firmware.uuid, since)}}
      end)
    else
      assign(socket, :failed_installs, AsyncResult.ok(nil))
    end
  end

  # Why the delete button is disabled, and what to warn about before it is
  # clicked. Both are recomputed whenever the firmware is reloaded — a
  # deployment group can start rolling this firmware out while the page is open.
  defp assign_deletion_state(socket, firmware) do
    socket
    |> assign(:deletion_blockers, Firmwares.deletion_blockers(firmware))
    |> assign(:deletion_warnings, Firmwares.deletion_warnings(firmware))
  end

  # A phx-change handler is required when using live uploads.
  @impl Phoenix.LiveView
  @decorate requires_membership()
  def handle_event("validate-firmware", _, socket), do: {:noreply, socket}

  @decorate requires_membership()
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    socket
    |> cancel_upload(:firmware, ref)
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("dismiss-upload-failure", %{"id" => id}, socket) do
    socket
    |> update(:upload_failures, fn failures -> Enum.reject(failures, &(&1.id == id)) end)
    |> noreply()
  end

  # Search and the two filters are one form. Any change starts again at
  # page 1, since the page the user was on may no longer exist.
  @decorate requires_membership()
  def handle_event("filter", params, socket) do
    filters =
      params
      |> Map.take(["search", "platform", "tool"])
      |> Map.new(fn {key, value} -> {key, blank_to_nil(value)} end)

    socket
    |> push_patch(to: self_path(socket, Map.put(filters, "page_number", nil)))
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("paginate", %{"page" => page_num}, socket) do
    params = %{"page_number" => page_num}

    socket
    |> push_patch(to: self_path(socket, params))
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("set-paginate-opts", %{"page-size" => page_size}, socket) do
    params = %{"page_size" => page_size, "page_number" => 1}

    socket
    |> push_patch(to: self_path(socket, params))
    |> noreply()
  end

  # Clicking the column already sorted on flips its direction; any other
  # column sorts newest or biggest first.
  @decorate requires_membership()
  def handle_event("sort", %{"sort" => value}, socket) do
    %{current_sort: current_sort, sort_direction: sort_direction} = socket.assigns

    direction =
      cond do
        value != current_sort -> "desc"
        sort_direction == "asc" -> "desc"
        true -> "asc"
      end

    socket
    |> push_patch(to: self_path(socket, %{"sort" => value, "sort_direction" => direction}))
    |> noreply()
  end

  # Opens the delete dialog. What blocks the delete and what goes with it are
  # looked up now rather than with the list, since only one row needs them.
  @decorate requires_permission(:"firmware:delete")
  def handle_event("prepare-delete", %{"firmware_uuid" => uuid}, socket) do
    %{current_scope: scope} = socket.assigns

    {:ok, firmware} = Firmwares.get_firmware_by_uuid(scope, uuid)

    install_count = running_count(socket.assigns, firmware)

    socket
    |> assign(:deleting, %{
      firmware: firmware,
      install_count: install_count,
      blockers: Firmwares.deletion_blockers(firmware),
      warnings: Firmwares.deletion_warnings(firmware)
    })
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("cancel-delete", _params, socket) do
    socket
    |> assign(:deleting, nil)
    |> noreply()
  end

  # the delete handler for the list page
  @decorate requires_permission(:"firmware:delete")
  def handle_event("delete-firmware", %{"firmware_uuid" => uuid}, socket) do
    %{current_scope: scope, product: product} = socket.assigns

    {:ok, firmware} = Firmwares.get_firmware_by_uuid(scope, uuid, include_deleted: true)

    case Firmwares.delete_firmware(firmware, scope.user) do
      {:ok, _} ->
        _ = ProductTemplates.audit_firmware_deleted(scope.user, product, firmware)

        socket
        |> assign(:deleting, nil)
        |> after_delete()
        |> put_flash(:info, "Firmware successfully deleted")
        |> noreply()

      # Something started using it between the dialog opening and the click,
      # so the dialog swaps its button for the reason.
      {:error, {:blocked, blockers}} ->
        socket
        |> update(:deleting, fn
          nil -> nil
          deleting -> %{deleting | blockers: blockers}
        end)
        |> then(fn socket ->
          if socket.assigns.live_action == :show, do: assign(socket, :deletion_blockers, blockers), else: socket
        end)
        |> put_flash(:error, FirmwareDeletion.blockers_message(blockers))
        |> noreply()

      {:error, %Ecto.Changeset{} = changeset} ->
        error_feedback(socket, changeset)
        |> noreply()
    end
  end

  @decorate requires_permission(:"deployment_group:update")
  def handle_event("retry-delta", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.deltas, &(to_string(&1.id) == id and &1.status in [:failed, :timed_out])) do
      nil ->
        noreply(socket)

      delta ->
        case Firmwares.retry_firmware_delta(delta) do
          {:ok, _} ->
            socket
            |> assign(:deltas, Firmwares.get_deltas_by_target_firmware(socket.assigns.firmware))
            |> put_flash(:info, "Building the delta from #{delta.source.version} again")
            |> noreply()

          {:error, _reason} ->
            socket
            |> put_flash(:error, "Couldn't start building the delta from #{delta.source.version}")
            |> noreply()
        end
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
      |> assign_firmware_list()
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
    |> assign_firmware_list()
    |> put_flash(
      :notice,
      "Firmware #{firmware.version} (#{String.slice(firmware.uuid, 0..7)}) has been deleted by another user."
    )
    |> noreply()
  end

  def handle_info(
        %Broadcast{topic: "product:" <> _product_id, event: "firmware/deleted", payload: %{firmware: deleted}},
        %{assigns: %{live_action: :show, current_scope: scope, firmware: firmware}} = socket
      )
      when deleted.id == firmware.id do
    firmware =
      scope
      |> Firmwares.get_firmware_by_uuid!(firmware.uuid, include_deleted: true)
      |> Firmwares.preload_deleted_by()

    socket
    |> assign_firmware_page(firmware)
    |> put_flash(:notice, "This firmware has been deleted by another user.")
    |> noreply()
  end

  # Ignore all other broadcasts
  def handle_info(_broadcast, socket) do
    {:noreply, socket}
  end

  @decorate requires_permission(:"firmware:upload")
  def handle_progress(:firmware, entry, socket) do
    if entry.done? do
      [filepath] =
        consume_uploaded_entries(socket, :firmware, fn %{path: path}, _entry ->
          {:ok, path}
        end)

      socket
      |> create_firmware(filepath, entry)
      |> noreply()
    else
      {:noreply, socket}
    end
  end

  # Uploading is only offered once per page visit. A patch (a tab, a filter, a
  # page) comes back through here, and allowing the upload again would drop a
  # file that is halfway up.
  defp allow_firmware_upload(%{assigns: %{uploads: %{firmware: _}}} = socket), do: socket

  defp allow_firmware_upload(socket) do
    allow_upload(socket, :firmware,
      # Every format's extension, or the file picker rejects it in the browser
      # before any of the upload code runs. See firmware_rauc_test.exs and
      # firmware_atom_vm_test.exs, both written after that happened.
      accept: ~w(.fw .bin .raucb .avm),
      max_entries: 1,
      auto_upload: true,
      max_file_size: max_file_size(),
      progress: &handle_progress/3,
      writer: fn _name, _entry, _socket -> {NervesHubWeb.BrieflyUploadWriter, parent: self()} end
    )
  end

  defp assign_firmware_list(socket) do
    %{assigns: %{product: product, params: params, current_scope: scope}} = socket

    tab = Map.get(@tabs, params["tab"], :all)
    sort = params["sort"] || "inserted_at"
    sort_direction = params["sort_direction"] || "desc"

    filters = %{
      search: blank_to_nil(params["search"]),
      platform: blank_to_nil(params["platform"]),
      tool: blank_to_nil(params["tool"])
    }

    opts =
      Map.merge(filters, %{
        tab: tab,
        sort: sort,
        sort_direction: sort_direction,
        page: params["page_number"],
        page_size: params["page_size"]
      })

    {entries, pager_meta} = Firmwares.list_firmware(product, opts)

    # A page past the end, usually left behind by deleting the last row on
    # it, shows the last page that has rows instead of an empty list.
    last_page = max(pager_meta.total_pages, 1)

    {entries, pager_meta, params} =
      if entries == [] and pager_meta.current_page > last_page do
        {entries, pager_meta} = Firmwares.list_firmware(product, %{opts | page: last_page})
        {entries, pager_meta, Map.put(params, "page_number", Integer.to_string(last_page))}
      else
        {entries, pager_meta, params}
      end

    socket
    |> assign(:params, params)
    |> assign(:tab, tab)
    |> assign(:filters, filters)
    |> assign(:current_sort, sort)
    |> assign(:sort_direction, sort_direction)
    |> assign(:firmware, entries)
    |> assign(:pager_meta, pager_meta)
    |> assign(:counts, Firmwares.list_counts(product))
    |> assign(:used_by, Firmwares.used_by(product, Enum.map(entries, & &1.id)))
    |> assign(:device_count, Devices.get_device_count_by_product_id(product.id))
    |> assign(:platforms, product |> Firmwares.get_unique_platforms() |> Enum.sort())
    |> assign(:tools, product |> Firmwares.get_unique_tools() |> Enum.sort())
    |> assign(:org_keys, Accounts.list_org_keys(scope))
  end

  defp self_path(socket, new_params), do: list_path(socket.assigns, new_params)

  # The list's path with the current params, changed by `new_params`. Every
  # link and patch on the list builds its path here.
  defp list_path(assigns, new_params) do
    current_params =
      assigns.params
      |> Map.reject(fn {key, _val} -> key in ["org_name", "product_name"] end)

    params =
      stringify_keys(new_params)
      |> Enum.into(current_params)
      # A nil value means "drop this param" rather than "set it to nothing".
      |> Map.reject(fn {_key, val} -> is_nil(val) end)

    ~p"/org/#{assigns.current_scope.org}/#{assigns.product}/firmware?#{params}"
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

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp viewing_first_page?(assigns) do
    case get_in(assigns, [:params, "page_number"]) do
      nil -> true
      page_number -> String.to_integer(page_number) == 1
    end
  end

  # A new upload goes to the top of the first page of everything, marked as
  # new, so it is in view whatever tab or page the user was on. A failed one
  # stays where it is, as a row above the list that says why.
  defp create_firmware(socket, filepath, entry) do
    %{org: org, product: product} = socket.assigns.current_scope

    case Firmwares.create_firmware(org, filepath, product: product) do
      {:ok, firmware} ->
        socket
        |> assign(:new_firmware_uuid, firmware.uuid)
        |> update(:upload_failures, fn failures -> Enum.reject(failures, &(&1.name == entry.client_name)) end)
        |> push_patch(to: ~p"/org/#{org}/#{product}/firmware")

      {:error, error} ->
        failure =
          error
          |> upload_failure(socket.assigns.current_scope)
          |> Map.merge(%{id: entry.ref, name: entry.client_name})

        update(socket, :upload_failures, fn failures ->
          [failure | Enum.reject(failures, &(&1.name == entry.client_name))]
        end)
    end
  end

  # What a failed upload's row says: a short title, the full reason, and where
  # to go to fix it when that is somewhere in NervesHub.
  defp upload_failure(error, scope) do
    message =
      case upload_error(error) do
        %Ecto.Changeset{} = changeset -> changeset_message(changeset)
        message -> message
      end

    Map.merge(%{message: message, action: nil}, upload_failure_kind(error, scope))
  end

  defp upload_failure_kind(:invalid_signature, scope) do
    %{title: "Bad signature", action: {"Signing keys", ~p"/org/#{scope.org}/settings/keys"}}
  end

  defp upload_failure_kind(:no_public_keys, scope) do
    %{title: "No signing keys", action: {"Signing keys", ~p"/org/#{scope.org}/settings/keys"}}
  end

  defp upload_failure_kind(:firmware_not_signed, scope) do
    %{title: "Not signed", action: {"Signing keys", ~p"/org/#{scope.org}/settings/keys"}}
  end

  defp upload_failure_kind({:update_tool_not_allowed, _tool, _product}, scope) do
    %{title: "Tool turned off", action: {"Product settings", ~p"/org/#{scope.org}/#{scope.product}/settings"}}
  end

  defp upload_failure_kind(%Ecto.Changeset{errors: [uuid: {"has already been taken", _}]}, _scope) do
    %{title: "Already uploaded"}
  end

  defp upload_failure_kind(_error, _scope), do: %{title: "Upload failed"}

  defp changeset_message(changeset) do
    Enum.map_join(changeset.errors, ", ", fn {_field, {message, _info}} -> message end)
  end

  # Turns whatever `create_firmware/3` failed with into something a user can act
  # on. A changeset is passed through untouched for `upload_failure/2` to render.
  defp upload_error(:no_public_keys) do
    "Please register public keys for verifying firmware signatures first"
  end

  defp upload_error(:invalid_signature) do
    "Firmware corrupt, signature invalid, or missing public key"
  end

  defp upload_error({:fwup_too_old, required, installed}) do
    "This firmware requires fwup #{required} or newer, and NervesHub has fwup #{installed}. " <>
      "Please contact support to have NervesHub's fwup updated."
  end

  defp upload_error({:product_mismatch, declared, expected}) do
    "This firmware is built for the product #{inspect(declared)}, but was uploaded to " <>
      "#{inspect(expected)}. Check the product name in your firmware build."
  end

  defp upload_error({:missing_manifest_field, field}) do
    "This RAUC bundle's manifest has no #{field}. NervesHub needs it to match " <>
      "the bundle to a deployment."
  end

  defp upload_error(:unsuitable_certificate_purpose) do
    "This bundle's signing certificate is not valid for signing. RAUC verifies " <>
      "with openssl's CMS, which expects a certificate usable for S/MIME " <>
      "signing — an `extendedKeyUsage` of `codeSigning` alone excludes that, " <>
      "and a device would refuse the bundle mid-install. Reissue the signing " <>
      "certificate without a restrictive extendedKeyUsage; `openssl x509 " <>
      "-purpose` should report \"S/MIME signing: Yes\"."
  end

  defp upload_error({:invalid_manifest_field, field}) do
    "This RAUC bundle's manifest has a #{field} that is not a UUID. NervesHub " <>
      "stores firmware identifiers in a UUID column, so a declared uuid has to " <>
      "be one — a UUIDv4 generated once per build is the usual answer."
  end

  defp upload_error({:missing_manifest_section, key}) do
    "This RAUC bundle's manifest has no [meta.nerveshub] section, so NervesHub " <>
      "cannot read #{key}. Meta sections require RAUC 1.9 or newer — older " <>
      "versions drop them silently while building the bundle, so the section " <>
      "can be present in your manifest and absent from the bundle."
  end

  defp upload_error(:plain_bundle_unsupported) do
    "This is a RAUC bundle in the plain format. NervesHub reads verity bundles, " <>
      "which is also the format required for the streaming installs that make " <>
      "RAUC worth using. Rebuild with `format=verity` in the manifest's " <>
      "[bundle] section."
  end

  # openssl said no for a reason NervesHub does not have a name for. Its own
  # message is the only thing that explains why, and it was previously dropped
  # on the floor — leaving an operator with "Unknown error uploading firmware"
  # and no way to tell a corrupt bundle from a broken openssl invocation.
  defp upload_error({:openssl_failed, status, output}) do
    Logger.error("openssl rejected a RAUC bundle (exit #{status}): #{output}")

    "NervesHub could not verify this RAUC bundle: openssl exited #{status}. " <>
      "If the bundle is not corrupt, the server log has openssl's own message."
  end

  defp upload_error({:temp_dir_unavailable, reason}) do
    Logger.error("could not create a temporary directory to verify a RAUC bundle: #{inspect(reason)}")

    "NervesHub could not create a temporary directory to verify this bundle. " <>
      "This is a server problem rather than something wrong with the bundle."
  end

  defp upload_error(:openssl_not_available) do
    "NervesHub could not run `openssl`, which it needs to read a RAUC bundle's " <>
      "signature. This is a server configuration problem rather than something " <>
      "wrong with the bundle — openssl has to be installed and on the path."
  end

  defp upload_error({:update_tool_not_allowed, tool, product}) do
    "The product #{inspect(product)} does not accept #{tool} firmware. " <>
      "An organization owner can enable it in the product's settings."
  end

  defp upload_error(:firmware_not_signed) do
    "This ESP-IDF image is not signed. Sign it with `espsecure.py sign_data --version 2` and register the matching public key against your organization, or allow unsigned images in this product's settings."
  end

  defp upload_error(:esp_idf_ecdsa_signatures_not_supported) do
    "This ESP-IDF image is signed with ECDSA. NervesHub can only verify RSA-3072 Secure Boot v2 signatures at present."
  end

  defp upload_error(:unknown_signature_block_version) do
    "This ESP-IDF image carries a signature block NervesHub does not recognise."
  end

  defp upload_error(:signature_block_corrupt) do
    "The signature block on this ESP-IDF image failed its checksum — the file is likely damaged in transit."
  end

  defp upload_error(:unrecognised_firmware_format) do
    "Unrecognised firmware format. This instance accepts #{UpdateTool.accepted_formats()}."
  end

  defp upload_error({:invalid_version, raw}) do
    "Firmware version #{inspect(raw)} is not a valid semantic version. " <>
      "For ESP-IDF, set PROJECT_VER in your CMakeLists.txt to something like \"1.2.3\"."
  end

  defp upload_error(%Ecto.Changeset{errors: [product_id: {"can't be blank", [validation: :required]}]}) do
    "No matching product could be found. Please check that your Nerves application product name " <>
      "(`:app` or `:name` in `mix.exs`) matches your #{Application.get_env(:nerves_hub, :web_title_suffix)} product name."
  end

  defp upload_error(%Ecto.Changeset{
         errors: [
           uuid: {"has already been taken", [constraint: :unique, constraint_name: "firmwares_product_id_uuid_index"]}
         ]
       }) do
    "Firmware UUID has already been taken, has this version been uploaded already?"
  end

  defp upload_error(%Ecto.Changeset{} = changeset), do: changeset
  defp upload_error(error) when is_binary(error), do: error
  defp upload_error(_error), do: "Unknown error uploading firmware. Please contact support."

  defp error_feedback(socket, %Ecto.Changeset{} = changeset) do
    put_flash(socket, :error, changeset_message(changeset))
  end

  defp max_file_size() do
    Application.get_env(:nerves_hub, Upload, [])[:max_size]
  end

  # The list's tabs, in order, with the count each shows.
  defp list_tabs(counts) do
    [
      %{key: :all, param: nil, label: "All", count: counts.all, dot: nil},
      %{key: :in_use, param: "in_use", label: "In use", count: counts.in_use, dot: "bg-success"},
      %{key: :not_in_use, param: "not_in_use", label: "Not in use", count: counts.not_in_use, dot: "bg-content-faint"},
      %{key: :deleted, param: "deleted", label: "Deleted", count: counts.deleted, dot: nil}
    ]
  end

  # A tab keeps the search and filters but starts again at page 1.
  defp tab_path(assigns, param) do
    list_path(assigns, %{"tab" => param, "page_number" => nil})
  end

  # The list path without one of the filters, for the "clear" links.
  defp without_filter_path(assigns, keys) do
    list_path(assigns, Map.new(["page_number" | keys], &{&1, nil}))
  end

  defp filtering?(filters), do: Enum.any?(filters, fn {_key, value} -> value end)

  # The start and end of a UUID, which is enough to tell builds apart.
  defp short_uuid(uuid) when byte_size(uuid) > 12 do
    String.slice(uuid, 0, 8) <> "…" <> String.slice(uuid, -4, 4)
  end

  defp short_uuid(uuid), do: uuid

  defp format_megabytes(nil), do: "—"

  defp format_megabytes(size) when size < 100_000 do
    "#{Float.round(size / 1_000, 1)} KB"
  end

  defp format_megabytes(size), do: "#{Float.round(size / 1_000_000, 1)} MB"

  # A share of the product's devices, rounded, with a sliver of fleet shown
  # as under 1% rather than 0%.
  defp share_of_devices(_count, 0), do: 0
  defp share_of_devices(0, _total), do: 0
  defp share_of_devices(count, total), do: max(round(count * 100 / total), 1)

  defp share_label(count, total) do
    case share_of_devices(count, total) do
      1 when count * 100 < total -> "<1%"
      share -> "#{share}%"
    end
  end

  defp delimited(number), do: Number.Delimit.number_to_delimited(number, precision: 0)

  # A part of a whole as a bar width, never wider than the bar.
  defp percent(_part, 0), do: 0
  defp percent(part, whole), do: min(part * 100 / whole, 100)

  # How much smaller than the full firmware a finished delta is.
  defp delta_saving(%{status: :completed, size: size, target_size: target_size}) when target_size > 0 and size > 0 do
    max(round((1 - size / target_size) * 100), 0)
  end

  defp delta_saving(_delta), do: nil

  defp delta_status(:completed), do: %{label: "Ready", dot: "bg-success", text: "text-content-body"}
  defp delta_status(:processing), do: %{label: "Building", dot: "bg-notice", text: "text-content-body"}
  defp delta_status(:failed), do: %{label: "Failed", dot: "bg-alert", text: "text-alert-content"}
  defp delta_status(:timed_out), do: %{label: "Timed out", dot: "bg-alert", text: "text-alert-content"}

  defp signing_key(%{org_key_id: nil}, _org_keys), do: :unsigned

  defp signing_key(%{org_key_id: org_key_id}, org_keys) do
    case Enum.find(org_keys, &(&1.id == org_key_id)) do
      nil -> :unknown
      key -> {:key, key.name}
    end
  end

  # Why the row menu's Delete is turned off, from what the list already knows.
  # The dialog asks again, since updates in flight are not in the list.
  defp delete_blocked_reason(firmware, used_by) do
    current =
      used_by
      |> Map.get(firmware.id, [])
      |> Enum.filter(&(&1.release == :current))
      |> Enum.map(& &1.deployment_group)

    if current != [], do: FirmwareDeletion.blocker_message({:current_release, current})
  end

  defp toggle_menu(uuid) do
    [
      to: "#firmware-#{uuid}-menu",
      in: {"ease-out duration-150", "opacity-0", "opacity-100"},
      out: {"ease-out duration-150", "opacity-100", "opacity-0"}
    ]
    |> JS.toggle()
    |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "#firmware-#{uuid}-menu-toggle")
  end

  defp hide_menu(js \\ %JS{}, uuid) do
    js
    |> JS.hide(to: "#firmware-#{uuid}-menu", transition: {"ease-out duration-150", "opacity-100", "opacity-0"})
    |> JS.set_attribute({"aria-expanded", "false"}, to: "#firmware-#{uuid}-menu-toggle")
  end

  # The firmware's page goes back to the list, since its firmware is gone; the
  # list reloads in place.
  defp after_delete(%{assigns: %{live_action: :show, current_scope: scope}} = socket) do
    push_patch(socket, to: ~p"/org/#{scope.org}/#{scope.product}/firmware")
  end

  defp after_delete(socket), do: assign_firmware_list(socket)

  # How many devices run the firmware the delete dialog is for: the page
  # already counted it, and the list has it on the firmware's row.
  defp running_count(%{live_action: :show, usage: usage}, _firmware), do: usage.running

  defp running_count(%{firmware: listed}, firmware) when is_list(listed) do
    case Enum.find(listed, &(&1.id == firmware.id)) do
      nil -> 0
      row -> row.install_count
    end
  end

  # The last two rows of a longer list open their menu upward, so it isn't
  # cut off by the bottom of the page.
  defp opens_up?(index, firmware) do
    count = length(firmware)
    count > 4 and index >= count - 2
  end

  attr(:deleting, :map, required: true, doc: "the firmware, its running count, and its deletion blockers and warnings")

  # Asks before deleting a firmware, from the list's row menu or the
  # firmware's page. When something blocks the delete it says what instead.
  defp delete_dialog(assigns) do
    ~H"""
    <NervesHubWeb.CoreComponents.modal id="delete-firmware-dialog" show on_cancel={JS.push("cancel-delete")}>
      <div class="flex max-w-lg flex-col gap-4">
        <div class="flex flex-col gap-1">
          <h2 id="delete-firmware-dialog-title" class="text-section-title text-content-strong">
            Delete <span class="font-mono">{@deleting.firmware.version}</span>
            <span class="font-mono text-sm font-normal text-content-muted">{@deleting.firmware.platform}</span>?
          </h2>
          <p id="delete-firmware-dialog-description" class="font-mono text-xs text-content-faint">{@deleting.firmware.uuid}</p>
        </div>

        <%= if @deleting.blockers != [] do %>
          <p class="rounded-card border border-alert/40 bg-alert-soft p-3 text-ui text-alert-content">
            {FirmwareDeletion.blockers_message(@deleting.blockers)}
          </p>
        <% else %>
          <ul class="flex flex-col gap-2 text-ui text-content-body">
            <li :if={@deleting.install_count > 0} class="flex gap-2">
              <span class="mt-0.5 lucide-cpu size-3.5 text-content-muted" aria-hidden="true"></span>
              <span>
                {ngettext("1 device runs it.", "%{count} devices run it.", @deleting.install_count)} They keep running it, but can’t download it again.
              </span>
            </li>
            <li :if={warning = FirmwareDeletion.warnings_message(@deleting.warnings)} class="flex gap-2">
              <span class="mt-0.5 lucide-git-compare size-3.5 text-content-muted" aria-hidden="true"></span>
              <span>{warning}</span>
            </li>
            <li class="flex gap-2">
              <span class="mt-0.5 lucide-archive size-3.5 text-content-muted" aria-hidden="true"></span>
              <span>The file is removed and can’t be restored. Its row stays under Deleted, so device history still says what ran.</span>
            </li>
          </ul>
        <% end %>

        <div class="flex justify-end gap-2">
          <.button phx-click={JS.exec("data-cancel", to: "#delete-firmware-dialog")}>Cancel</.button>
          <.button :if={@deleting.blockers == []} style="danger-solid" phx-click="delete-firmware" phx-value-firmware_uuid={@deleting.firmware.uuid}>
            Delete firmware
          </.button>
        </div>
      </div>
    </NervesHubWeb.CoreComponents.modal>
    """
  end

  attr(:pager, :map, required: true)
  attr(:can_upload, :boolean, default: false)

  # Sends `set-paginate-opts` and `paginate`, like the shared pager does.
  defp list_footer(assigns) do
    %{current_page: page, page_size: size, total_count: total} = assigns.pager
    last_page = max(assigns.pager.total_pages, 1)

    assigns =
      assign(assigns,
        first: (page - 1) * size + 1,
        last: min(page * size, total),
        last_page: last_page
      )

    ~H"""
    <div id="firmware-pager" class="flex items-center justify-between gap-4 px-4 pb-6 @3xl:px-6">
      <p class="min-w-0 truncate font-mono text-xs text-content-body">
        {@first}–{@last} of {@pager.total_count}<span :if={@can_upload} class="max-sm:hidden"><span class="text-content-faint"> · </span><span class="font-sans text-ui text-content-muted">Drop a .fw, .bin, .raucb or .avm file anywhere on this page to upload it</span></span>
      </p>

      <div class="flex shrink-0 items-center gap-4">
        <form id="firmware-page-size" phx-change="set-paginate-opts" class="flex items-center gap-1.5">
          <label for="firmware-page-size-select" class="text-ui text-content-body max-sm:hidden">Per page</label>
          <span class="grid grid-cols-1">
            <select
              id="firmware-page-size-select"
              name="page-size"
              aria-label="Firmware per page"
              class="col-start-1 row-start-1 h-7 cursor-pointer appearance-none rounded-sm border border-line-control bg-surface-raised bg-none py-0 pr-6 pl-2 font-mono text-xs text-content-strong focus:outline focus:-outline-offset-1 focus:outline-focus-ring"
            >
              <option :for={option <- [25, 50, 100]} value={option} selected={option == @pager.page_size}>{option}</option>
            </select>
            <span class="pointer-events-none col-start-1 row-start-1 mr-1.5 lucide-chevron-down size-3 self-center justify-self-end text-content-muted" aria-hidden="true"></span>
          </span>
        </form>

        <nav aria-label="Pages" class="flex items-center">
          <button
            type="button"
            aria-label="Previous page"
            disabled={@pager.current_page < 2}
            phx-click="paginate"
            phx-value-page={@pager.current_page - 1}
            class="flex size-7 shrink-0 items-center justify-center rounded-l-sm border border-line-control bg-surface-raised text-content-body enabled:cursor-pointer enabled:hover:bg-surface-muted disabled:border-line-default disabled:text-content-faint"
          >
            <span class="lucide-chevron-left size-3.5" aria-hidden="true"></span>
          </button>
          <span aria-current="page" class="flex h-7 items-center border-y border-line-default bg-surface-raised px-2.5 font-mono text-xs whitespace-nowrap text-content-strong">
            {@pager.current_page} / {@last_page}
          </span>
          <button
            type="button"
            aria-label="Next page"
            disabled={@pager.current_page >= @last_page}
            phx-click="paginate"
            phx-value-page={@pager.current_page + 1}
            class="flex size-7 shrink-0 items-center justify-center rounded-r-sm border border-line-control bg-surface-raised text-content-body enabled:cursor-pointer enabled:hover:bg-surface-muted disabled:border-line-default disabled:text-content-faint"
          >
            <span class="lucide-chevron-right size-3.5" aria-hidden="true"></span>
          </button>
        </nav>
      </div>
    </div>
    """
  end

  attr(:field, :string, required: true)
  attr(:current, :string, required: true)
  attr(:direction, :string, required: true)

  defp sort_arrow(assigns) do
    ~H"""
    <span
      :if={@field == @current}
      class={["size-3 text-content-body", (@direction == "asc" && "lucide-arrow-up") || "lucide-arrow-down"]}
      aria-label={(@direction == "asc" && "ascending") || "descending"}
    ></span>
    """
  end

  # Within the last day, how long ago; before that, the day.
  defp uploaded_label(at, time_zone) do
    if NaiveDateTime.diff(NaiveDateTime.utc_now(), at, :hour) < 24 do
      from_now(at)
    else
      day_label(at, time_zone)
    end
  end

  defp empty_tab_message(:in_use),
    do: "No devices are running any of this product’s firmware, and no deployment group releases it."

  defp empty_tab_message(:not_in_use), do: "All of this product’s firmware is in use."
  defp empty_tab_message(:deleted), do: "No firmware has been deleted."
  defp empty_tab_message(_tab), do: "This product has no firmware that isn’t deleted."

  defp upload_progress_label(entry) do
    done = round(entry.client_size * entry.progress / 100)
    "#{format_megabytes(done)} of #{format_megabytes(entry.client_size)}"
  end
end
