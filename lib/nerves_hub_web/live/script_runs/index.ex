defmodule NervesHubWeb.Live.ScriptRuns.Index do
  use NervesHubWeb, :live_view

  alias NervesHub.ScriptRunners
  alias NervesHub.ScriptRunners.ScriptRunner
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

  # Newest first: a run has no name to sort by, and the most recent one is nearly
  # always what someone came to look at.
  @default_sorting %{sort_direction: "desc", sort: "inserted_at"}
  @sort_types %{sort_direction: :string, sort: :string}

  @default_filters %{
    search: ""
  }

  @filter_types %{
    search: :string
  }

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket
    |> page_title("Script Runs - #{socket.assigns.current_scope.product.name}")
    |> assign(:paginate_opts, @default_pagination)
    |> assign(:sort_direction, @default_sorting.sort_direction)
    |> assign(:current_sort, @default_sorting.sort)
    |> assign(:current_filters, @default_filters)
    |> assign(:currently_filtering, false)
    # Shares the sidebar entry with the scripts listing -- the two are tabs of
    # one page, so the sidebar should not move when switching between them.
    |> sidebar_tab(:support_scripts)
    |> assign(:tab, :runs)
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    pagination_changes = pagination_changes(params)
    pagination_opts = Map.merge(@default_pagination, pagination_changes)
    filters = Map.merge(@default_filters, filter_changes(params))

    socket
    |> assign(:params, params)
    |> assign(:paginate_opts, pagination_opts)
    |> assign(:current_sort, Map.get(params, "sort", @default_sorting.sort))
    |> assign(:sort_direction, Map.get(params, "sort_direction", @default_sorting.sort_direction))
    |> assign(:current_filters, filters)
    |> assign(:currently_filtering, filters != @default_filters)
    |> assign_runs_with_pagination()
    |> noreply()
  end

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

  @impl Phoenix.LiveView
  def handle_event("update-filters", params, %{assigns: %{paginate_opts: paginate_opts}} = socket) do
    page_params = %{"page_number" => @default_page, "page_size" => paginate_opts.page_size}

    socket
    |> push_patch(to: self_path(socket, Map.merge(params, page_params)))
    |> noreply()
  end

  # Handles event of user clicking the same field that is already sorted
  # For this case, we switch the sorting direction of same field
  @impl Phoenix.LiveView
  def handle_event("sort", %{"sort" => value}, %{assigns: %{current_sort: current_sort}} = socket)
      when value == current_sort do
    %{sort_direction: sort_direction} = socket.assigns

    sort_direction = if sort_direction == "desc", do: "asc", else: "desc"
    params = %{sort_direction: sort_direction, sort: value}

    socket
    |> push_patch(to: self_path(socket, params))
    |> noreply()
  end

  # User has clicked a new column to sort
  @impl Phoenix.LiveView
  def handle_event("sort", %{"sort" => value}, socket) do
    new_params = %{sort_direction: "asc", sort: value}

    socket
    |> push_patch(to: self_path(socket, new_params))
    |> noreply()
  end

  defp assign_runs_with_pagination(socket) do
    %{
      assigns: %{
        current_scope: scope,
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

    {entries, pager_meta} = ScriptRunners.filter(scope, opts)

    socket
    |> assign(:script_runs, entries)
    |> assign(:pager_meta, pager_meta)
  end

  defp self_path(socket, new_params) do
    params = Enum.into(stringify_keys(new_params), socket.assigns.params)
    pagination = pagination_changes(params)
    sort = sort_changes(params)
    filter = filter_changes(params)

    query =
      filter
      |> Map.merge(pagination)
      |> Map.merge(sort)

    ~p"/org/#{socket.assigns.current_scope.org}/#{socket.assigns.current_scope.product}/scripts/runs?#{query}"
  end

  defp pagination_changes(params) do
    Ecto.Changeset.cast(
      {@default_pagination, @pagination_types},
      params,
      Map.keys(@default_pagination)
    ).changes
  end

  defp sort_changes(params) do
    Ecto.Changeset.cast({@default_sorting, @sort_types}, params, Map.keys(@default_sorting)).changes
  end

  defp filter_changes(params) do
    Ecto.Changeset.cast({@default_filters, @filter_types}, params, Map.keys(@default_filters), empty_values: []).changes
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
end
