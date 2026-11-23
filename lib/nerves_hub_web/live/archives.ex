defmodule NervesHubWeb.Live.Archives do
  use NervesHubWeb, :live_view

  import NervesHubWeb.Components.ProductList

  alias NervesHub.Accounts
  alias NervesHub.Archives
  alias NervesHub.Archives.Archive
  alias NervesHub.Branding
  alias NervesHub.Uploads
  alias NervesHubWeb.Components.Dialog
  alias NervesHubWeb.Mounts.RequireEveryDevice

  on_mount(RequireEveryDevice)

  embed_templates("archive_templates/*")

  # The tabs a `tab` param can name. Anything else, or none, is every archive.
  @tabs %{"delivered" => :delivered, "not_delivered" => :not_delivered}

  @impl Phoenix.LiveView
  @decorate requires_membership()
  def mount(_params, _session, socket) do
    socket
    |> assign(:product, socket.assigns.current_scope.product)
    |> assign(:upload_failures, [])
    |> assign(:new_archive_uuid, nil)
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
    |> page_title("Archives - #{product.name}")
    |> sidebar_tab(:archives)
    |> assign(:params, unsigned_params)
    |> allow_archive_upload()
    |> assign_archive_list()
    |> render_with(&list_archives_template/1)
  end

  defp apply_action(%{assigns: %{product: product}} = socket, :show, %{"archive_uuid" => archive_uuid}) do
    archive = Archives.get_by_product_and_uuid!(product, archive_uuid)

    socket
    |> page_title("Archive #{archive.version} (#{short_uuid(archive.uuid)}) - #{product.name}")
    |> sidebar_tab(:archives)
    |> assign(:org_keys, Accounts.list_org_keys(socket.assigns.current_scope))
    |> assign_archive_page(archive)
    |> render_with(&show_archive_template/1)
  end

  # Everything the archive's page shows besides the archive itself: who it
  # reaches and every release that has included it.
  defp assign_archive_page(socket, archive) do
    releases = socket.assigns.product |> Archives.releases([archive.id]) |> Map.get(archive.id, [])

    socket
    |> assign(:archive, archive)
    |> assign(:delivery, Archives.delivery(archive))
    |> assign(:releases, releases)
  end

  # A phx-change handler is required when using live uploads.
  @impl Phoenix.LiveView
  @decorate requires_membership()
  def handle_event("validate-archive", _, socket), do: {:noreply, socket}

  @decorate requires_membership()
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    socket
    |> cancel_upload(:archive, ref)
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("dismiss-upload-failure", %{"id" => id}, socket) do
    socket
    |> update(:upload_failures, fn failures -> Enum.reject(failures, &(&1.id == id)) end)
    |> noreply()
  end

  # Search and the platform filter are one form. Any change starts again at
  # page 1, since the page the user was on may no longer exist.
  @decorate requires_membership()
  def handle_event("filter", params, socket) do
    filters =
      params
      |> Map.take(["search", "platform"])
      |> Map.new(fn {key, value} -> {key, blank_to_nil(value)} end)

    socket
    |> push_patch(to: list_path(socket.assigns, Map.put(filters, "page_number", nil)))
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("paginate", %{"page" => page_num}, socket) do
    socket
    |> push_patch(to: list_path(socket.assigns, %{"page_number" => page_num}))
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("set-paginate-opts", %{"page-size" => page_size}, socket) do
    socket
    |> push_patch(to: list_path(socket.assigns, %{"page_size" => page_size, "page_number" => 1}))
    |> noreply()
  end

  # Clicking the column already sorted on flips its direction; any other
  # column sorts newest first.
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
    |> push_patch(to: list_path(socket.assigns, %{"sort" => value, "sort_direction" => direction}))
    |> noreply()
  end

  # Opens the delete dialog. Whether a release has used the archive is looked
  # up again now, since one may have been made since the page loaded.
  @decorate requires_permission(:"archive:delete")
  def handle_event("prepare-delete", %{"archive_uuid" => uuid}, socket) do
    {:ok, archive} = Archives.get(socket.assigns.product, uuid)

    socket
    |> assign(:deleting, %{archive: archive, blocked_by: release_groups(socket.assigns.product, archive)})
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("cancel-delete", _params, socket) do
    socket
    |> assign(:deleting, nil)
    |> noreply()
  end

  @decorate requires_permission(:"archive:delete")
  def handle_event("delete-archive", %{"archive_uuid" => uuid}, socket) do
    %{current_scope: scope, product: product} = socket.assigns

    {:ok, archive} = Archives.get(product, uuid)

    case Archives.delete_archive(archive) do
      {:ok, _} ->
        socket
        |> assign(:deleting, nil)
        |> put_flash(:info, "#{archive_name(archive)} #{archive.version} was deleted")
        |> after_delete(scope)
        |> noreply()

      {:error, _} ->
        socket
        |> delete_failed(product, archive)
        |> noreply()
    end
  end

  # A release that started using the archive between the dialog opening and
  # the click is the usual reason, and the dialog swaps its button for it. Any
  # other failure, such as the file's cleanup job not being queued, leaves the
  # dialog as it was so the delete can be tried again.
  defp delete_failed(socket, product, archive) do
    case release_groups(product, archive) do
      [] ->
        put_flash(socket, :error, "#{archive_name(archive)} #{archive.version} couldn’t be deleted. Try again.")

      blocked_by ->
        socket
        |> update(:deleting, fn
          nil -> nil
          deleting -> %{deleting | blocked_by: blocked_by}
        end)
        |> put_flash(:error, blocked_message(blocked_by))
    end
  end

  @decorate requires_permission(:"archive:upload")
  def handle_progress(:archive, entry, socket) do
    if entry.done? do
      # BrieflyUploadWriter streams the upload straight to a temp file it hands to
      # this LiveView, so we consume the entry and use that path directly — no
      # copy, and no postpone/clear dance to keep the default temp alive.
      [filepath] =
        consume_uploaded_entries(socket, :archive, fn %{path: path}, _entry ->
          {:ok, path}
        end)

      socket
      |> create_archive(filepath, entry)
      |> noreply()
    else
      {:noreply, socket}
    end
  end

  # Uploading is only offered once per page visit. A patch (a tab, a filter, a
  # page) comes back through here, and allowing the upload again would drop a
  # file that is halfway up.
  defp allow_archive_upload(%{assigns: %{uploads: %{archive: _}}} = socket), do: socket

  defp allow_archive_upload(socket) do
    allow_upload(socket, :archive,
      accept: ~w(.fw),
      max_entries: 1,
      auto_upload: true,
      max_file_size: max_file_size(),
      progress: &handle_progress/3,
      writer: fn _name, _entry, _socket -> {NervesHubWeb.BrieflyUploadWriter, parent: self()} end
    )
  end

  defp assign_archive_list(socket) do
    %{assigns: %{product: product, params: params, current_scope: scope}} = socket

    tab = Map.get(@tabs, params["tab"], :all)
    sort = params["sort"] || "inserted_at"
    sort_direction = params["sort_direction"] || "desc"
    filters = %{search: blank_to_nil(params["search"]), platform: blank_to_nil(params["platform"])}

    opts =
      Map.merge(filters, %{
        tab: tab,
        sort: sort,
        sort_direction: sort_direction,
        page: params["page_number"],
        page_size: params["page_size"]
      })

    {entries, pager_meta} = Archives.list_archives(product, opts)

    # A page past the end, usually left behind by deleting the last row on
    # it, shows the last page that has rows instead of an empty list.
    last_page = max(pager_meta.total_pages, 1)

    {entries, pager_meta, params} =
      if entries == [] and pager_meta.current_page > last_page do
        {entries, pager_meta} = Archives.list_archives(product, %{opts | page: last_page})
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
    |> assign(:archives, entries)
    |> assign(:pager_meta, pager_meta)
    |> assign(:counts, Archives.list_counts(product))
    |> assign(:releases, Archives.releases(product, Enum.map(entries, & &1.id)))
    |> assign(:platforms, Archives.platforms(product))
    |> assign(:org_keys, Accounts.list_org_keys(scope))
  end

  # The list's path with the current params, changed by `new_params`.
  defp list_path(assigns, new_params) do
    params =
      assigns.params
      |> Map.reject(fn {key, _val} -> key in ["org_name", "product_name"] end)
      |> Map.merge(Map.new(new_params, fn {key, value} -> {to_string(key), value} end))
      # A nil value means "drop this param" rather than "set it to nothing".
      |> Map.reject(fn {_key, val} -> is_nil(val) end)

    ~p"/org/#{assigns.current_scope.org}/#{assigns.product}/archives?#{params}"
  end

  # A tab keeps the search and filter but starts again at page 1.
  defp tab_path(assigns, param), do: list_path(assigns, %{"tab" => param, "page_number" => nil})

  # The list path without one of the filters, for the "clear" links.
  defp without_filter_path(assigns, key), do: list_path(assigns, %{key => nil, "page_number" => nil})

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp filtering?(filters), do: Enum.any?(filters, fn {_key, value} -> value end)

  # A new upload goes to the top of the first page of everything, marked as
  # new, so it is in view whatever tab or page the user was on. A failed one
  # stays where it is, as a row above the list that says why.
  defp create_archive(socket, filepath, entry) do
    %{org: org, product: product} = socket.assigns.current_scope

    case Archives.create(product, filepath) do
      {:ok, archive} ->
        socket
        |> assign(:new_archive_uuid, archive.uuid)
        |> update(:upload_failures, fn failures -> Enum.reject(failures, &(&1.name == entry.client_name)) end)
        |> push_patch(to: ~p"/org/#{org}/#{product}/archives")

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

  # What a failed upload's row says: a short title, the full reason, where to
  # go to fix it when that is somewhere in NervesHub, and whether it's the
  # file's fault (`:alert`) or NervesHub's (`:warning`).
  defp upload_failure(:invalid_signature, scope) do
    %{
      title: "Bad signature",
      tone: :alert,
      message:
        "It’s corrupt, or isn’t signed with any of #{scope.org.name}’s signing keys. " <>
          "Check the file, sign it with one of them, or add the key it was signed with.",
      action: {"Signing keys", ~p"/org/#{scope.org}/settings/keys"}
    }
  end

  defp upload_failure(:no_public_keys, scope) do
    %{
      title: "No signing keys",
      tone: :alert,
      message:
        "#{scope.org.name} has no signing keys yet. Add the key the archive was signed with, then upload it again.",
      action: {"Signing keys", ~p"/org/#{scope.org}/settings/keys"}
    }
  end

  defp upload_failure({:fwup_too_old, required, installed}, _scope) do
    %{
      title: "fwup too old",
      tone: :warning,
      message:
        "It needs fwup #{required} or newer, and #{Branding.friendly_platform_name()} has #{installed}. " <>
          "Ask support to update #{Branding.friendly_platform_name()}’s fwup.",
      action: nil
    }
  end

  defp upload_failure(%Ecto.Changeset{errors: [uuid: _]} = changeset, scope) do
    uuid = Ecto.Changeset.get_field(changeset, :uuid)

    case Archives.get(scope.product, uuid) do
      {:ok, existing} ->
        %{
          title: "Already uploaded",
          tone: :alert,
          message: "This archive is already here: #{archive_name(existing)} #{existing.version} has the same UUID.",
          action: {"Open #{existing.version}", ~p"/org/#{scope.org}/#{scope.product}/archives/#{existing}"}
        }

      {:error, :not_found} ->
        %{
          title: "Already uploaded",
          tone: :alert,
          message: "An archive with this UUID was already uploaded.",
          action: nil
        }
    end
  end

  defp upload_failure(%Ecto.Changeset{} = changeset, _scope) do
    message = Enum.map_join(changeset.errors, ", ", fn {field, {message, _info}} -> "#{field} #{message}" end)
    %{title: "Upload failed", tone: :alert, message: "The archive’s metadata was refused: #{message}.", action: nil}
  end

  defp upload_failure(message, _scope) when is_binary(message) do
    %{title: "Upload failed", tone: :alert, message: message, action: nil}
  end

  defp upload_failure(_error, _scope) do
    %{
      title: "Upload failed",
      tone: :alert,
      message: "Unknown error uploading the archive. Please contact support if this happens again.",
      action: nil
    }
  end

  defp max_file_size() do
    Application.get_env(:nerves_hub, Uploads, [])[:max_size]
  end

  # The list's tabs, in order, with the count each shows.
  defp list_tabs(counts) do
    [
      %{key: :all, param: nil, label: "All", count: counts.all, dot: nil},
      %{key: :delivered, param: "delivered", label: "Delivered", count: counts.delivered, dot: "bg-success"},
      %{
        key: :not_delivered,
        param: "not_delivered",
        label: "Not delivered",
        count: counts.not_delivered,
        dot: "bg-content-faint"
      }
    ]
  end

  defp empty_tab_message(:delivered), do: "No deployment group’s current release includes an archive."
  defp empty_tab_message(:not_delivered), do: "Every archive is in a current release."
  defp empty_tab_message(_tab), do: "This product has no archives."

  # What the archive is called: its description, which is where fwup keeps a
  # human name. Without one, all there is to go on is the version.
  defp archive_name(%Archive{description: description}) when description not in [nil, ""], do: description
  defp archive_name(_archive), do: "Archive"

  defp signing_key(%{org_key_id: org_key_id}, org_keys) do
    case Enum.find(org_keys, &(&1.id == org_key_id)) do
      nil -> :unknown
      key -> {:key, key.name}
    end
  end

  # The current releases that send an archive to devices.
  defp current_releases(releases, archive_id) do
    releases |> Map.get(archive_id, []) |> Enum.filter(& &1.current?)
  end

  # The groups whose releases, past or current, have included the archive.
  defp release_groups(product, archive) do
    product
    |> Archives.releases([archive.id])
    |> Map.get(archive.id, [])
    |> blocking_groups()
  end

  defp blocking_groups(releases) do
    releases
    |> Enum.map(& &1.deployment_group)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.name)
  end

  # Why the row menu's Delete is turned off, from what the list already knows.
  defp delete_blocked_reason(archive, releases) do
    releases
    |> Map.get(archive.id, [])
    |> blocking_groups()
    |> case do
      [] ->
        nil

      groups ->
        "It’s in releases of #{join_names(groups)}. An archive that any release has used can’t be deleted."
    end
  end

  defp blocked_message(groups) do
    "Releases in #{join_names(groups)} use this archive, so it can’t be deleted. " <>
      "Past releases count too, since a group’s history keeps them."
  end

  defp join_names(groups) do
    case Enum.map(groups, & &1.name) do
      [name] -> name
      names -> Enum.join(Enum.drop(names, -1), ", ") <> " and " <> List.last(names)
    end
  end

  defp delimited(number), do: Number.Delimit.number_to_delimited(number, precision: 0)

  # A part of a whole as a bar width, never wider than the bar.
  defp percent(_part, 0), do: 0
  defp percent(part, whole), do: min(part * 100 / whole, 100)

  defp toggle_menu(uuid) do
    [
      to: "#archive-#{uuid}-menu",
      in: {"ease-out duration-150", "opacity-0", "opacity-100"},
      out: {"ease-out duration-150", "opacity-100", "opacity-0"}
    ]
    |> JS.toggle()
    |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "#archive-#{uuid}-menu-toggle")
  end

  defp hide_menu(js \\ %JS{}, uuid) do
    js
    |> JS.hide(to: "#archive-#{uuid}-menu", transition: {"ease-out duration-150", "opacity-100", "opacity-0"})
    |> JS.set_attribute({"aria-expanded", "false"}, to: "#archive-#{uuid}-menu-toggle")
  end

  # The archive's page goes back to the list, since its archive is gone; the
  # list reloads in place.
  defp after_delete(%{assigns: %{live_action: :show}} = socket, scope) do
    push_patch(socket, to: ~p"/org/#{scope.org}/#{scope.product}/archives")
  end

  defp after_delete(socket, _scope), do: assign_archive_list(socket)

  # The last two rows of a longer list open their menu upward, so it isn't
  # cut off by the bottom of the page.
  defp opens_up?(index, archives) do
    count = length(archives)
    count > 4 and index >= count - 2
  end

  defp upload_progress_label(entry) do
    done = round(entry.client_size * entry.progress / 100)
    "#{format_megabytes(done)} of #{format_megabytes(entry.client_size)}"
  end

  attr(:deleting, :map, required: true, doc: "the archive, and the groups whose releases have used it")

  # Asks before deleting an archive, from the list's row menu or the archive's
  # page. When a release has used it, it says so instead.
  defp delete_dialog(assigns) do
    ~H"""
    <Dialog.confirm id="delete-archive-dialog" on_cancel={JS.push("cancel-delete")} wide>
      <:heading>
        Delete {archive_name(@deleting.archive)} <span class="font-mono">{@deleting.archive.version}</span>
        for <span class="font-mono">{@deleting.archive.platform} · {@deleting.archive.architecture}</span>?
      </:heading>
      <:subtitle><span class="font-mono">{@deleting.archive.uuid}</span></:subtitle>

      <%= if @deleting.blocked_by != [] do %>
        <p class="rounded-card border border-alert/40 bg-alert-soft p-3 text-alert-content">
          {blocked_message(@deleting.blocked_by)}
        </p>
      <% else %>
        <p>The file is removed for good. Archives have no Deleted tab, so to get it back you would upload the file again.</p>
        <ul class="flex flex-col gap-1.5 rounded-card bg-surface-muted px-3 py-2.5 text-content-body">
          <li class="flex items-center gap-2"><.status_dot class="size-1.5 bg-content-faint" /> No release has ever used it</li>
          <li class="flex items-center gap-2"><.status_dot class="size-1.5 bg-content-faint" /> No device is sent it</li>
          <li class="flex items-center gap-2"><.status_dot class="size-1.5 bg-content-faint" /> Its UUID is free to upload again</li>
        </ul>
      <% end %>

      <:actions :if={@deleting.blocked_by == []}>
        <.button style="danger-solid" phx-click="delete-archive" phx-value-archive_uuid={@deleting.archive.uuid}>
          Delete archive
        </.button>
      </:actions>
    </Dialog.confirm>
    """
  end
end
