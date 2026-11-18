defmodule NervesHubWeb.Live.Product.Errors do
  @moduledoc """
  Every error a product's fleet has reported, as a queue to work through.

  Rows come from PostgreSQL — `NervesHub.ErrorReports.ErrorGroup` is one row per
  distinct error, which is what makes this page a list rather than an
  aggregation over every crash in the fleet. The sparkline and the device
  count are the figures that need ClickHouse, so they load after the rows, in
  one task for the page, and show a dash if it doesn't answer.

  Filters live in the URL. "Show me the unresolved ones sorted by count" is the
  view somebody wants to send to somebody else.
  """

  use NervesHubWeb, :live_view

  import NervesHubWeb.Components.ErrorReports
  import NervesHubWeb.Components.Fleet, only: [delimited: 1]

  alias NervesHub.AuditLogs.ProductTemplates
  alias NervesHub.ErrorReports
  alias NervesHub.Helpers.RelativeTime
  alias NervesHubWeb.Helpers.Timezone
  alias NervesHubWeb.Mounts.RequireEveryDevice

  on_mount(RequireEveryDevice)

  @statuses ~w(unresolved muted resolved)
  @sorts ~w(last_seen first_seen count)
  @page_sizes [25, 50, 100]
  @sparkline_days 14
  @restored_on_undo [:regressed_at, :resolved_at, :resolved_by_id, :resolved_in_firmware_uuid]

  @impl Phoenix.LiveView
  @decorate requires_membership()
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    socket
    |> assign(:product, scope.product)
    |> assign(:extension_enabled?, scope.product.extensions.error_reports)
    |> assign(:page_title, "#{scope.product.name} Errors")
    |> assign(:undo, nil)
    |> assign(:stats, :loading)
    |> sidebar_tab(:errors)
    |> ok()
  end

  @impl Phoenix.LiveView
  @decorate requires_membership()
  def handle_params(params, _uri, socket) do
    socket
    |> assign(:status_filter, filter_value(params, "status", @statuses, "unresolved"))
    |> assign(:sort, filter_value(params, "sort", @sorts, "last_seen"))
    |> assign(:search, params |> Map.get("search", "") |> String.trim())
    |> assign(:firmware_filter, Map.get(params, "firmware", ""))
    |> assign(:page_number, integer_param(params, "page_number", 1))
    |> assign(:page_size, page_size_param(params))
    |> fetch_groups()
    |> noreply()
  end

  @impl Phoenix.LiveView
  @decorate requires_membership()
  def handle_event("filter", params, socket) do
    socket
    |> patch_to(%{
      "sort" => Map.get(params, "sort", socket.assigns.sort),
      "search" => Map.get(params, "search", socket.assigns.search),
      "firmware" => Map.get(params, "firmware", socket.assigns.firmware_filter),
      "page_number" => "1"
    })
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("paginate", %{"page" => page}, socket) do
    socket
    |> patch_to(%{"page_number" => page})
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("set-paginate-opts", %{"page-size" => page_size}, socket) do
    socket
    |> patch_to(%{"page_size" => page_size, "page_number" => "1"})
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("dismiss-undo", _params, socket) do
    socket
    |> assign(:undo, nil)
    |> noreply()
  end

  @decorate requires_permission(:"error_group:update")
  def handle_event("resolve", %{"id" => id}, socket), do: act(socket, id, :resolve)
  @decorate requires_permission(:"error_group:update")
  def handle_event("mute", %{"id" => id}, socket), do: act(socket, id, :mute)
  @decorate requires_permission(:"error_group:update")
  def handle_event("reopen", %{"id" => id}, socket), do: act(socket, id, :reopen)

  @decorate requires_permission(:"error_group:update")
  def handle_event("undo", _params, %{assigns: %{undo: nil}} = socket), do: noreply(socket)

  @decorate requires_permission(:"error_group:update")
  def handle_event("undo", _params, %{assigns: %{current_scope: scope, undo: undo}} = socket) do
    group = ErrorReports.get_group!(scope.product, undo.group_id)

    if still_as_left?(group, undo) do
      apply_undo(socket, group, undo)
    else
      # It came back, or someone else changed it, since. Putting back what it
      # was before would throw that away.
      socket
      |> assign(:undo, nil)
      |> put_flash(:info, "#{undo.name} has changed since, so it was left as it is.")
      |> fetch_groups()
      |> noreply()
    end
  end

  defp apply_undo(%{assigns: %{current_scope: scope}} = socket, group, undo) do
    case ErrorReports.reopen(group, undo_options(undo)) do
      {:ok, updated} ->
        _ = ProductTemplates.audit_error_group_reopened(scope.user, scope.product, updated)

        socket
        |> assign(:undo, nil)
        |> fetch_groups()
        |> noreply()

      {:error, _changeset} ->
        socket
        |> put_flash(:error, "The error could not be updated. Please try again.")
        |> noreply()
    end
  end

  defp undo_options(%{restore: restore}), do: Map.to_list(restore)

  defp still_as_left?(group, %{left: {status, at}}) do
    group.status == status and DateTime.compare(changed_at(group), at) == :eq
  end

  defp changed_at(%{status: :resolved} = group), do: group.resolved_at
  defp changed_at(%{status: :muted} = group), do: group.muted_at
  defp changed_at(_group), do: nil

  @impl Phoenix.LiveView
  def handle_async(:stats, {:ok, {fingerprints, stats}}, socket) do
    # A result for rows that are no longer on screen is dropped.
    if fingerprints == Enum.map(socket.assigns.groups, & &1.fingerprint) do
      socket
      |> assign(:stats, stats)
      |> noreply()
    else
      noreply(socket)
    end
  end

  # Not shown as zero: no devices and "ClickHouse didn't answer" are different
  # facts, and only one of them is worth acting on.
  def handle_async(:stats, _failed, socket) do
    socket
    |> assign(:stats, :failed)
    |> noreply()
  end

  defp act(%{assigns: %{current_scope: scope}} = socket, id, action) do
    group = ErrorReports.get_group!(scope.product, id)

    case apply_action(action, group, scope.user) do
      {:ok, updated} ->
        _ = audit(action, scope, updated)

        socket
        |> assign(:undo, undo(action, group, updated))
        |> put_flash_for(action)
        |> fetch_groups()
        |> noreply()

      {:error, _changeset} ->
        socket
        |> put_flash(:error, "The error could not be updated. Please try again.")
        |> noreply()
    end
  end

  # Resolving and muting take the row off this tab, so they come with an undo
  # instead of a flash. Reopening and unmuting are their own undo.
  #
  # A regressed error still carries the resolve it came back from, and
  # resolving clears the regression, so undo puts back both rather than
  # leaving a plain unresolved error.
  #
  # `left` is the state the action left the error in, so an undo can tell when
  # it has moved on since.
  defp undo(action, group, updated) when action in [:resolve, :mute] do
    %{
      action: action,
      group_id: group.id,
      name: short_name(group.reason),
      restore: Map.take(group, @restored_on_undo),
      left: {updated.status, changed_at(updated)}
    }
  end

  defp undo(_action, _group, _updated), do: nil

  defp put_flash_for(socket, :reopen), do: put_flash(socket, :info, "Error moved back to Unresolved.")
  defp put_flash_for(socket, _action), do: socket

  defp apply_action(:resolve, group, user), do: ErrorReports.resolve(group, user)
  defp apply_action(:mute, group, user), do: ErrorReports.mute(group, user)
  defp apply_action(:reopen, group, _user), do: ErrorReports.reopen(group)

  defp audit(:resolve, scope, group), do: ProductTemplates.audit_error_group_resolved(scope.user, scope.product, group)

  defp audit(:mute, scope, group), do: ProductTemplates.audit_error_group_muted(scope.user, scope.product, group)

  defp audit(:reopen, scope, group), do: ProductTemplates.audit_error_group_reopened(scope.user, scope.product, group)

  defp fetch_groups(%{assigns: %{extension_enabled?: false}} = socket) do
    socket
    |> assign(:groups, [])
    |> assign(:result_meta, %Flop.Meta{})
    |> assign(:status_counts, %{unresolved: 0, resolved: 0, muted: 0})
  end

  defp fetch_groups(%{assigns: assigns} = socket) do
    filters = [search: assigns.search, firmware: assigns.firmware_filter]

    {groups, meta} =
      ErrorReports.groups_for_product(
        assigns.product,
        [
          status: status_option(assigns.status_filter),
          sort: sort_option(assigns.sort),
          page: assigns.page_number,
          page_size: assigns.page_size
        ] ++ filters
      )

    last_page = max(meta.total_pages, 1)

    if groups == [] and assigns.page_number > last_page do
      # Past the last page, which resolving or muting the only row on it
      # leaves you: show the last page there is, not an empty tab without a
      # pager to get back with.
      socket
      |> assign(:page_number, last_page)
      |> fetch_groups()
    else
      assign_groups(socket, groups, meta, filters)
    end
  end

  defp assign_groups(%{assigns: assigns} = socket, groups, meta, filters) do
    status_counts = ErrorReports.status_counts(assigns.product)

    socket
    |> assign(:groups, groups)
    |> assign(:result_meta, meta)
    |> assign(:status_counts, status_counts)
    |> assign(:versions, ErrorReports.last_seen_versions(assigns.product))
    |> assign(:firmware, ErrorReports.firmware_by_uuid(assigns.product, Enum.map(groups, & &1.last_seen_firmware_uuid)))
    |> assign(:match_counts, match_counts(assigns, groups, filters))
    |> assign(:last_resolved_at, last_resolved_at(assigns, groups, status_counts))
    |> start_stats(groups)
  end

  # Only when a search or filter has emptied the tab, to say where its matches
  # are instead.
  defp match_counts(assigns, [], filters) do
    if filtering?(assigns), do: ErrorReports.status_counts(assigns.product, filters)
  end

  defp match_counts(_assigns, _groups, _filters), do: nil

  defp last_resolved_at(%{status_filter: "unresolved"} = assigns, [], %{unresolved: 0, resolved: resolved})
       when resolved > 0 do
    if !filtering?(assigns), do: ErrorReports.last_resolved_at(assigns.product)
  end

  defp last_resolved_at(_assigns, _groups, _counts), do: nil

  defp start_stats(socket, []), do: assign(socket, :stats, %{})

  defp start_stats(socket, groups) do
    product = socket.assigns.product
    time_zone = Timezone.resolve(socket.assigns[:time_zone])

    socket
    |> assign(:stats, :loading)
    |> start_async(:stats, fn ->
      {Enum.map(groups, & &1.fingerprint), ErrorReports.list_stats(product, groups, @sparkline_days, time_zone)}
    end)
  end

  defp patch_to(%{assigns: assigns} = socket, overrides) do
    params = assigns |> current_params() |> Map.merge(overrides) |> compact()
    scope = assigns.current_scope

    push_patch(socket, to: ~p"/org/#{scope.org}/#{scope.product}/errors?#{params}")
  end

  defp current_params(assigns) do
    %{
      "status" => assigns.status_filter,
      "sort" => assigns.sort,
      "search" => assigns.search,
      "firmware" => assigns.firmware_filter,
      "page_number" => to_string(assigns.page_number),
      "page_size" => to_string(assigns.page_size)
    }
  end

  defp compact(params) do
    params
    |> Enum.reject(fn {key, value} ->
      value in [nil, ""] or
        {key, value} in [{"status", "unresolved"}, {"sort", "last_seen"}, {"page_number", "1"}, {"page_size", "25"}]
    end)
    |> Map.new()
  end

  @doc false
  def list_path(assigns, overrides) do
    params = assigns |> current_params() |> Map.put("page_number", "1") |> Map.merge(overrides) |> compact()
    scope = assigns.current_scope

    ~p"/org/#{scope.org}/#{scope.product}/errors?#{params}"
  end

  defp filter_value(params, key, allowed, default) do
    value = Map.get(params, key)
    if value in allowed, do: value, else: default
  end

  defp integer_param(params, key, default) do
    case Integer.parse(Map.get(params, key, "")) do
      {value, ""} when value > 0 -> value
      _ -> default
    end
  end

  defp page_size_param(params) do
    size = integer_param(params, "page_size", 25)
    if size in @page_sizes, do: size, else: 25
  end

  @doc false
  def filtering?(assigns), do: assigns.search != "" or assigns.firmware_filter != ""

  @doc "The tabs, in order, with their labels."
  def status_options(), do: [{"Unresolved", "unresolved"}, {"Muted", "muted"}, {"Resolved", "resolved"}]

  @doc """
  The atom a filter value names.

  Spelled out rather than reached through `String.to_existing_atom/1`. The
  clauses below are the only place some of these appear as literals — the
  defaults are matched with a variable — so whether the atom exists at all
  depends on what else the VM happens to have loaded, which is a page that
  works on one boot and raises on the next.
  """
  def status_option("resolved"), do: :resolved
  def status_option("muted"), do: :muted
  def status_option(_unresolved), do: :unresolved

  @doc "The atom a sort value names. See `status_option/1` for why it is spelled out."
  def sort_option("count"), do: :count
  def sort_option("first_seen"), do: :first_seen
  def sort_option(_last_seen), do: :last_seen

  @doc """
  The versions the firmware filter offers: those errors were last seen on,
  plus the one filtered on if the URL names another.
  """
  def firmware_options(versions, ""), do: versions
  def firmware_options(versions, filter), do: Enum.uniq(versions ++ [filter])

  # The header row is uppercase and tracked; a tooltip under it reads as a
  # sentence. A dotted underline says a header has one.
  @doc false
  def header_tip_class(), do: "w-max max-w-64 text-left normal-case tracking-normal text-content-body"

  @doc false
  def header_tip_trigger_class(), do: "underline decoration-content-faint decoration-dotted underline-offset-3"

  @doc "The orderings the page offers."
  def sort_options(), do: [{"Last seen", "last_seen"}, {"First seen", "first_seen"}, {"Events", "count"}]

  @doc false
  def sort_label(sort), do: Enum.find_value(sort_options(), fn {label, value} -> value == sort && label end)

  @doc false
  def page_sizes(), do: @page_sizes

  @doc false
  def stat(:loading, _group, _key), do: :loading
  def stat(:failed, _group, _key), do: :failed

  def stat(stats, group, :daily) do
    case Map.fetch(stats, group.fingerprint) do
      {:ok, %{daily: daily}} -> daily
      :error -> List.duplicate(0, @sparkline_days)
    end
  end

  def stat(stats, group, :device_count) do
    case Map.fetch(stats, group.fingerprint) do
      {:ok, %{device_count: count}} -> count
      :error -> 0
    end
  end

  @doc false
  def hot?(group), do: badge_kind(group) in [:regressed, :new]

  @doc false
  def last_seen_label(at), do: RelativeTime.from_now(at)

  @doc "What sits under a muted or resolved error's top frame: who, when, and what since."
  def status_note(%{status: :muted} = group, time_zone) do
    "Muted#{by(group.muted_by)} · #{day_label(group.muted_at, time_zone)} · still counting"
  end

  def status_note(%{status: :resolved} = group, time_zone) do
    "Resolved#{by(group.resolved_by)} · #{day_label(group.resolved_at, time_zone)} · not seen since"
  end

  def status_note(_group, _time_zone), do: nil

  defp by(%{name: name}), do: " by #{name}"
  defp by(_user), do: ""

  @doc """
  Where a search's matches are when none are on this tab:
  "Matches 3 muted and 1 resolved."
  """
  def match_summary(counts, current) do
    others =
      for {label, value} <- status_options(),
          status_option(value) != current,
          Map.get(counts, status_option(value), 0) > 0 do
        "#{Map.get(counts, status_option(value))} #{String.downcase(label)}"
      end

    case others do
      [] -> nil
      [one] -> "Matches #{one}."
      many -> "Matches #{Enum.join(Enum.drop(many, -1), ", ")} and #{List.last(many)}."
    end
  end

  @doc false
  def empty_tab(:muted),
    do:
      {"Nothing muted",
       "Mute an error you know about and don’t want in the queue. It keeps counting and never reopens."}

  def empty_tab(:resolved),
    do: {"Nothing resolved", "Resolve an error once you’ve shipped a fix. If it happens again it reopens as Regressed."}

  @doc false
  def toast_message(%{action: :resolve}), do: "It reopens as Regressed if it happens again."
  def toast_message(%{action: :mute}), do: "It keeps counting and won’t reopen."

  @doc false
  def toast_verb(%{action: :resolve}), do: "Resolved"
  def toast_verb(%{action: :mute}), do: "Muted"
end
