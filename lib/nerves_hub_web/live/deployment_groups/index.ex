defmodule NervesHubWeb.Live.DeploymentGroups.Index do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup

  alias NervesHubWeb.Components.Pager
  alias NervesHubWeb.Components.Sorting
  alias NervesHubWeb.Components.FilterSidebar

  @default_filters %{
    name: "",
    platform: "",
    architecture: "",
    search: ""
  }

  @filter_types %{
    name: :string,
    platform: :string,
    architecture: :string,
    search: :string
  }

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

  @default_sorting %{sort_direction: "asc", sort: "name"}
  @sort_types %{sort_direction: :string, sort: :string}

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{product: product}} = socket) do
    deployment_groups = ManagedDeployments.get_deployment_groups_by_product(product)
    counts = ManagedDeployments.get_device_counts_by_product(product)

    deployment_groups =
      deployment_groups
      |> Enum.sort_by(& &1.name)
      |> Enum.group_by(fn deployment_group ->
        deployment_group.firmware.platform
      end)

    socket
    |> page_title("Deployments - #{product.name}")
    |> assign(:paginate_opts, @default_pagination)
    |> assign(:sort_direction, @default_sorting.sort_direction)
    |> assign(:current_sort, @default_sorting.sort)
    |> sidebar_tab(:deployments)
    |> assign(:deployment_groups, deployment_groups)
    |> assign(:platforms, Firmwares.get_unique_platforms(product))
    |> assign(:architectures, Firmwares.get_unique_architectures(product))
    |> assign(:counts, counts)
    |> assign(:current_filters, @default_filters)
    |> assign(:currently_filtering, false)
    |> assign(:show_filters, false)
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    filters = Map.merge(@default_filters, filter_changes(params))
    pagination_changes = pagination_changes(params)
    pagination_opts = Map.merge(@default_pagination, pagination_changes)

    socket
    |> assign(:params, params)
    |> assign(:current_sort, Map.get(params, "sort", @default_sorting.sort))
    |> assign(
      :sort_direction,
      Map.get(params, "sort_direction", @default_sorting.sort_direction)
    )
    |> assign(:current_filters, filters)
    |> assign(:currently_filtering, filters != @default_filters)
    |> assign(:paginate_opts, pagination_opts)
    |> assign_deployment_groups_with_pagination()
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
  def handle_event("toggle-filters", %{"toggle" => toggle}, socket) do
    {:noreply, assign(socket, :show_filters, toggle != "true")}
  end

  @impl Phoenix.LiveView
  def handle_event(
        "update-filters",
        params,
        socket
      ) do
    socket
    |> push_patch(to: self_path(socket, params))
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_event("reset-filters", _params, socket) do
    socket
    |> push_patch(to: self_path(socket, @default_filters))
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
    new_params = %{sort_direction: "asc", sort: value}

    socket
    |> push_patch(to: self_path(socket, new_params))
    |> noreply()
  end

  defp assign_deployment_groups_with_pagination(socket) do
    %{
      assigns: %{
        product: product,
        current_filters: filters,
        paginate_opts: paginate_opts
      }
    } = socket

    opts = %{
      pagination: %{page: paginate_opts.page_number, page_size: paginate_opts.page_size},
      sort:
        {String.to_existing_atom(socket.assigns.sort_direction),
         String.to_atom(socket.assigns.current_sort)},
      filters: filters
    }

    {entries, pager_meta} = ManagedDeployments.filter(product, opts)

    socket
    |> assign(:entries, entries)
    |> assign(:pager_meta, pager_meta)
  end

  defp self_path(socket, new_params) do
    params = Enum.into(stringify_keys(new_params), socket.assigns.params)
    pagination = pagination_changes(params)
    filter = filter_changes(params)
    sort = sort_changes(params)

    query =
      filter
      |> Map.merge(pagination)
      |> Map.merge(sort)

    ~p"/org/#{socket.assigns.org.name}/#{socket.assigns.product.name}/deployment_groups?#{query}"
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

  defp sort_changes(params) do
    Ecto.Changeset.cast({@default_sorting, @sort_types}, params, Map.keys(@default_sorting)).changes
  end

  defp filter_changes(params) do
    Ecto.Changeset.cast({@default_filters, @filter_types}, params, Map.keys(@default_filters),
      empty_values: []
    ).changes
  end

  defp pagination_changes(params) do
    Ecto.Changeset.cast(
      {@default_pagination, @pagination_types},
      params,
      Map.keys(@default_pagination)
    ).changes
  end

  defp firmware_simple_display_name(%Firmware{} = f) do
    "#{f.version} #{f.uuid}"
  end

  defp version(%DeploymentGroup{conditions: %{"version" => ""}}), do: "-"
  defp version(%DeploymentGroup{conditions: %{"version" => version}}), do: version

  defp tags(%DeploymentGroup{conditions: %{"tags" => tags}}), do: tags
end
