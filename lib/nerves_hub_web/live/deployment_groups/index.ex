defmodule NervesHubWeb.Live.DeploymentGroups.Index do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup

  alias NervesHubWeb.Components.Pager
  alias NervesHubWeb.Components.Sorting

  @pagination_opts ["page_number", "page_size", "sort", "sort_direction"]
  @default_filters %{
    name: ""
  }

  @filter_types %{
    name: :string
  }

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
    |> sidebar_tab(:deployments)
    |> assign(:deployment_groups, deployment_groups)
    |> assign(:counts, counts)
    |> assign(:current_filters, @default_filters)
    |> assign(:currently_filtering, false)
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    filters = Map.merge(@default_filters, filter_changes(params))

    socket
    |> assign(:params, params)
    |> assign(:current_filters, filters)
    |> assign(:currently_filtering, filters != @default_filters)
    |> assign_deployment_groups_with_pagination()
    |> noreply()
  end

  defp filter_changes(params) do
    Ecto.Changeset.cast({@default_filters, @filter_types}, params, Map.keys(@default_filters),
      empty_values: []
    ).changes
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
  def handle_event(
        "update-filters",
        params,
        socket
      ) do
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
    new_params = %{sort_direction: "asc", sort: value}

    socket
    |> push_patch(to: self_path(socket, new_params))
    |> noreply()
  end

  defp assign_deployment_groups_with_pagination(socket) do
    %{assigns: %{product: product, params: params, current_filters: filters}} = socket

    pagination_opts = Map.take(params, @pagination_opts)

    opts = %{
      page: pagination_opts["page_number"],
      page_size: pagination_opts["page_size"],
      sort: pagination_opts["sort"] || "name",
      sort_direction: pagination_opts["sort_direction"],
      filters: filters
    }

    {entries, pager_meta} = ManagedDeployments.filter(product, opts)

    socket
    |> assign(:current_sort, opts.sort)
    |> assign(:sort_direction, opts.sort_direction)
    |> assign(:entries, entries)
    |> assign(:pager_meta, pager_meta)
  end

  defp self_path(socket, new_params) do
    current_params =
      socket.assigns.params
      |> Map.reject(fn {key, _val} -> key in ["org_name", "product_name"] end)

    params =
      stringify_keys(new_params)
      |> Enum.into(current_params)

    ~p"/org/#{socket.assigns.org.name}/#{socket.assigns.product.name}/deployment_groups?#{params}"
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

  defp firmware_simple_display_name(%Firmware{} = f) do
    "#{f.version} #{f.uuid}"
  end

  defp version(%DeploymentGroup{conditions: %{"version" => ""}}), do: "-"
  defp version(%DeploymentGroup{conditions: %{"version" => version}}), do: version

  defp tags(%DeploymentGroup{conditions: %{"tags" => tags}}), do: tags
end
