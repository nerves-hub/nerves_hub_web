defmodule NervesHubWeb.Live.ScriptRuns.Show do
  @moduledoc """
  One run: what it ran, which devices it chose, and what each of them said.

  The device results are paginated, searchable by identifier and sortable, the
  same way the listings are. A run can be tens of thousands of devices wide, so
  nothing here loads the whole result set — including the live updates, which
  refresh the status counts (one grouped query) and leave the visible page of rows
  where the operator put it.
  """

  use NervesHubWeb, :live_view

  alias NervesHub.ScriptRunners
  alias NervesHub.ScriptRunners.ScriptRunner
  alias NervesHub.ScriptRunners.ScriptRunnerDevice
  alias NervesHub.Scripts.Script
  alias NervesHubWeb.Components.Sorting

  @default_page 1
  @default_page_size 25

  @default_pagination %{
    page_number: @default_page,
    page_size: @default_page_size,
    page_sizes: [25, 50, 100],
    total_pages: 0
  }

  @pagination_types %{
    page_number: :integer,
    page_size: :integer,
    page_sizes: {:array, :integer},
    total_pages: :integer
  }

  # Identifier ascending: the one column a person scans, and the order they would
  # look a device up in.
  @default_sorting %{sort_direction: "asc", sort: "identifier"}
  @sort_types %{sort_direction: :string, sort: :string}

  @default_filters %{identifier: "", status: ""}
  @filter_types %{identifier: :string, status: :string}

  @impl Phoenix.LiveView
  def mount(%{"script_run_id" => id}, _session, %{assigns: %{current_scope: scope}} = socket) do
    run = ScriptRunners.get_by_id!(scope, id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(NervesHub.PubSub, ScriptRunners.topic(run))
    end

    socket
    |> page_title("#{run.name} - #{scope.product.name}")
    # Shares the sidebar entry with the scripts listing, like the runs index.
    |> sidebar_tab(:support_scripts)
    |> assign(:script_run, run)
    |> assign(:status_counts, ScriptRunners.status_counts(run))
    |> assign(:expanded_device_id, nil)
    |> assign(:paginate_opts, @default_pagination)
    |> assign(:sort_direction, @default_sorting.sort_direction)
    |> assign(:current_sort, @default_sorting.sort)
    |> assign(:current_filters, @default_filters)
    |> assign(:currently_filtering, false)
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    pagination_opts = Map.merge(@default_pagination, pagination_changes(params))
    filters = Map.merge(@default_filters, filter_changes(params))

    socket
    |> assign(:params, params)
    |> assign(:paginate_opts, pagination_opts)
    |> assign(:current_sort, Map.get(params, "sort", @default_sorting.sort))
    |> assign(:sort_direction, Map.get(params, "sort_direction", @default_sorting.sort_direction))
    |> assign(:current_filters, filters)
    |> assign(:currently_filtering, filters != @default_filters)
    |> assign_devices_with_pagination()
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_event("paginate", %{"page" => page_num}, socket) do
    socket
    |> push_patch(to: self_path(socket, %{"page_number" => page_num}))
    |> noreply()
  end

  def handle_event("set-paginate-opts", %{"page-size" => page_size}, socket) do
    socket
    |> push_patch(to: self_path(socket, %{"page_size" => page_size, "page_number" => 1}))
    |> noreply()
  end

  def handle_event("update-filters", params, %{assigns: %{paginate_opts: paginate_opts}} = socket) do
    page_params = %{"page_number" => @default_page, "page_size" => paginate_opts.page_size}

    socket
    |> push_patch(to: self_path(socket, Map.merge(params, page_params)))
    |> noreply()
  end

  # Clicking the column already sorted reverses it.
  def handle_event("sort", %{"sort" => value}, %{assigns: %{current_sort: value}} = socket) do
    sort_direction = if socket.assigns.sort_direction == "desc", do: "asc", else: "desc"

    socket
    |> push_patch(to: self_path(socket, %{sort_direction: sort_direction, sort: value}))
    |> noreply()
  end

  def handle_event("sort", %{"sort" => value}, socket) do
    socket
    |> push_patch(to: self_path(socket, %{sort_direction: "asc", sort: value}))
    |> noreply()
  end

  # Output is often long and sometimes many lines, so it is revealed a row at a
  # time rather than given a column. Clicking the open row closes it.
  def handle_event("toggle-output", %{"id" => id}, socket) do
    # The browser sends the value as a string; a test pushing the event directly
    # sends whatever it was given.
    id = if is_binary(id), do: String.to_integer(id), else: id
    expanded = if socket.assigns.expanded_device_id != id, do: id

    socket
    |> assign(:expanded_device_id, expanded)
    |> noreply()
  end

  # Only the counts are refreshed as devices report. Reloading the visible page of
  # rows on every device would re-query a paginated table once per device, and a
  # run can be tens of thousands of devices wide.
  @impl Phoenix.LiveView
  def handle_info({:script_runner, :device_finished, _payload}, socket) do
    socket
    |> assign(:status_counts, ScriptRunners.status_counts(socket.assigns.script_run))
    |> noreply()
  end

  # The run's own status changed, which the header shows.
  def handle_info({:script_runner, event, _payload}, socket) when event in [:started, :finished] do
    run = ScriptRunners.get_by_id!(socket.assigns.current_scope, socket.assigns.script_run.id)

    socket
    |> assign(:script_run, run)
    |> assign(:status_counts, ScriptRunners.status_counts(run))
    |> noreply()
  end

  def handle_info(_message, socket), do: noreply(socket)

  defp assign_devices_with_pagination(socket) do
    %{
      assigns: %{
        script_run: run,
        paginate_opts: paginate_opts,
        sort_direction: sort_direction,
        current_sort: current_sort,
        current_filters: current_filters
      }
    } = socket

    opts = %{
      pagination: %{page: paginate_opts.page_number, page_size: paginate_opts.page_size},
      sort: {String.to_existing_atom(sort_direction), String.to_existing_atom(current_sort)},
      filters: current_filters
    }

    {entries, pager_meta} = ScriptRunners.filter_devices(run, opts)

    socket
    |> assign(:device_results, entries)
    |> assign(:pager_meta, pager_meta)
  end

  defp self_path(socket, new_params) do
    params = Enum.into(stringify_keys(new_params), socket.assigns.params)

    query =
      params
      |> filter_changes()
      |> Map.merge(pagination_changes(params))
      |> Map.merge(sort_changes(params))

    scope = socket.assigns.current_scope

    ~p"/org/#{scope.org}/#{scope.product}/scripts/runs/#{socket.assigns.script_run.id}?#{query}"
  end

  defp pagination_changes(params) do
    Ecto.Changeset.cast({@default_pagination, @pagination_types}, params, Map.keys(@default_pagination)).changes
  end

  defp sort_changes(params) do
    Ecto.Changeset.cast({@default_sorting, @sort_types}, params, Map.keys(@default_sorting)).changes
  end

  defp filter_changes(params) do
    Ecto.Changeset.cast({@default_filters, @filter_types}, params, Map.keys(@default_filters), empty_values: []).changes
  end

  defp stringify_keys(params) do
    for {key, value} <- params, into: %{} do
      if is_atom(key), do: {to_string(key), value}, else: {key, value}
    end
  end

  # Every status a device result can hold, for the progress counts and the status
  # filter to offer. The schema's own order, so the two always agree.
  defp statuses(), do: ScriptRunnerDevice.statuses()

  defp status_count(counts, status), do: Map.get(counts, status, 0)

  # Devices that reached an outcome, of any kind -- a failure is as finished as a
  # success. Only `:pending` and `:running` are not counted, being the two statuses
  # a device can still move off.
  defp finished_count(counts) do
    counts
    |> Map.take(ScriptRunnerDevice.terminal_statuses())
    |> count_values()
  end

  # Every device the run has a row for, counted the same way as the numerator so
  # the two always agree.
  defp total_count(counts), do: count_values(counts)

  defp count_values(counts), do: counts |> Map.values() |> Enum.sum()

  defp devices(1), do: "device"
  defp devices(_many), do: "devices"
end
