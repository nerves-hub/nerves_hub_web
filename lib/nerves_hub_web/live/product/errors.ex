defmodule NervesHubWeb.Live.Product.Errors do
  @moduledoc """
  Every error a product's fleet has reported, as a queue to work through.

  Rows come from PostgreSQL — `NervesHub.ErrorReports.ErrorGroup` is one row per
  distinct error, which is what makes this page a list rather than an
  aggregation over every crash in the fleet. The affected-device count is the
  one figure that does need ClickHouse, so it is loaded asynchronously and the
  page does not wait for it.

  Filters live in the URL. "Show me the unresolved ones sorted by count" is the
  view somebody wants to send to somebody else.
  """

  use NervesHubWeb, :live_view

  alias NervesHub.AuditLogs.ProductTemplates
  alias NervesHub.ErrorReports
  alias NervesHub.ErrorReports.ErrorGroup

  @statuses ~w(unresolved resolved muted)
  @sorts ~w(last_seen first_seen count)

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    socket
    |> assign(:product, scope.product)
    |> assign(:extension_enabled?, scope.product.extensions.error_reports)
    |> assign(:page_title, "#{scope.product.name} Errors")
    |> sidebar_tab(:errors)
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    socket
    |> assign(:status_filter, filter_value(params, "status", @statuses, "unresolved"))
    |> assign(:sort, filter_value(params, "sort", @sorts, "last_seen"))
    |> assign(:search, Map.get(params, "search", ""))
    |> assign(:page_number, integer_param(params, "page_number", 1))
    |> assign(:page_size, integer_param(params, "page_size", 25))
    |> fetch_groups()
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_event("filter", params, socket) do
    socket
    |> patch_to(%{
      "status" => Map.get(params, "status", socket.assigns.status_filter),
      "sort" => Map.get(params, "sort", socket.assigns.sort),
      "search" => Map.get(params, "search", socket.assigns.search),
      "page_number" => "1"
    })
    |> noreply()
  end

  def handle_event("paginate", %{"page" => page}, socket) do
    socket
    |> patch_to(%{"page_number" => page})
    |> noreply()
  end

  def handle_event("set-paginate-opts", %{"page-size" => page_size}, socket) do
    socket
    |> patch_to(%{"page_size" => page_size, "page_number" => "1"})
    |> noreply()
  end

  def handle_event("resolve", %{"id" => id}, socket), do: act(socket, id, :resolve)
  def handle_event("mute", %{"id" => id}, socket), do: act(socket, id, :mute)
  def handle_event("reopen", %{"id" => id}, socket), do: act(socket, id, :reopen)

  @impl Phoenix.LiveView
  def handle_async({:device_count, group_id}, {:ok, count}, socket) do
    socket
    |> assign(:device_counts, Map.put(socket.assigns.device_counts, group_id, count))
    |> noreply()
  end

  # A count that could not be fetched is left absent rather than shown as zero.
  # Zero devices and "ClickHouse did not answer" are different facts, and only
  # one of them is worth acting on.
  def handle_async(_name, _result, socket), do: {:noreply, socket}

  defp act(%{assigns: %{current_scope: scope}} = socket, id, action) do
    authorized!(:"error_group:update", scope)

    group = ErrorReports.get_group!(scope.product, id)

    case apply_action(action, group, scope.user) do
      {:ok, updated} ->
        _ = audit(action, scope, updated)

        socket
        |> put_flash(:info, flash_message(action))
        |> fetch_groups()
        |> noreply()

      {:error, _changeset} ->
        socket
        |> put_flash(:error, "The error could not be updated. Please try again.")
        |> noreply()
    end
  end

  defp apply_action(:resolve, group, user), do: ErrorReports.resolve(group, user)
  defp apply_action(:mute, group, user), do: ErrorReports.mute(group, user)
  defp apply_action(:reopen, group, _user), do: ErrorReports.reopen(group)

  defp audit(:resolve, scope, group), do: ProductTemplates.audit_error_group_resolved(scope.user, scope.product, group)

  defp audit(:mute, scope, group), do: ProductTemplates.audit_error_group_muted(scope.user, scope.product, group)

  defp audit(:reopen, scope, group), do: ProductTemplates.audit_error_group_reopened(scope.user, scope.product, group)

  defp flash_message(:resolve), do: "Error marked as resolved."
  defp flash_message(:mute), do: "Error muted."
  defp flash_message(:reopen), do: "Error reopened."

  defp fetch_groups(%{assigns: %{extension_enabled?: false}} = socket) do
    socket
    |> assign(:groups, [])
    |> assign(:result_meta, %Flop.Meta{})
    |> assign(:status_counts, %{unresolved: 0, resolved: 0, muted: 0})
  end

  defp fetch_groups(%{assigns: assigns} = socket) do
    {groups, meta} =
      ErrorReports.groups_for_product(assigns.product,
        status: String.to_existing_atom(assigns.status_filter),
        sort: String.to_existing_atom(assigns.sort),
        search: assigns.search,
        page: assigns.page_number,
        page_size: assigns.page_size
      )

    socket
    |> assign(:groups, groups)
    |> assign(:result_meta, meta)
    |> assign(:status_counts, ErrorReports.status_counts(assigns.product))
    |> assign_device_counts(groups)
  end

  # One async query per visible row, not one per issue in the product. The count
  # is the only thing on this page that needs ClickHouse, and nothing on the
  # page is unreadable while it is missing.
  defp assign_device_counts(socket, groups) do
    Enum.reduce(groups, socket, fn group, socket ->
      start_async(socket, {:device_count, group.id}, fn ->
        ErrorReports.affected_device_count(group)
      end)
    end)
    |> assign(:device_counts, %{})
  end

  defp patch_to(%{assigns: assigns} = socket, overrides) do
    params =
      %{
        "status" => assigns.status_filter,
        "sort" => assigns.sort,
        "search" => assigns.search,
        "page_number" => to_string(assigns.page_number),
        "page_size" => to_string(assigns.page_size)
      }
      |> Map.merge(overrides)
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    scope = assigns.current_scope

    push_patch(socket, to: ~p"/org/#{scope.org}/#{scope.product}/errors?#{params}")
  end

  defp filter_value(params, key, allowed, default) do
    case Map.get(params, key) do
      value when value in ["", nil] -> default
      value -> if value in allowed, do: value, else: default
    end
  end

  defp integer_param(params, key, default) do
    case Integer.parse(Map.get(params, key, "")) do
      {value, ""} when value > 0 -> value
      _ -> default
    end
  end

  @doc "The statuses the filter offers, with their labels."
  def status_options(), do: [{"Unresolved", "unresolved"}, {"Resolved", "resolved"}, {"Muted", "muted"}]

  @doc "The orderings the page offers."
  def sort_options(), do: [{"Last seen", "last_seen"}, {"First seen", "first_seen"}, {"Occurrences", "count"}]

  @doc "Tailwind classes for a status pill."
  def status_class(:unresolved), do: "bg-base-800 text-orange-400"
  def status_class(:resolved), do: "bg-base-800 text-success"
  def status_class(:muted), do: "bg-base-800 text-base-400"

  @doc "The innermost frame, rendered for a list row."
  def top_frame(%ErrorGroup{top_frame_module: nil}), do: nil

  def top_frame(%ErrorGroup{} = group) do
    location =
      if group.top_frame_file do
        " (#{group.top_frame_file}:#{group.top_frame_line})"
      else
        ""
      end

    "#{group.top_frame_module}.#{group.top_frame_function}#{location}"
  end
end
