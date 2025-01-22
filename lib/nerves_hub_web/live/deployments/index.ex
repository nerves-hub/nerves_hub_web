defmodule NervesHubWeb.Live.Deployments.Index do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Deployments
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Firmwares.Firmware

  alias NervesHubWeb.Components.Pager
  alias NervesHubWeb.Components.Sorting

  @pagination_opts ["page_number", "page_size", "sort", "sort_direction"]

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{product: product}} = socket) do
    deployments = Deployments.get_deployments_by_product(product)
    counts = Deployments.get_device_counts_by_product(product)

    deployments =
      deployments
      |> Enum.sort_by(& &1.name)
      |> Enum.group_by(fn deployment ->
        deployment.firmware.platform
      end)

    socket
    |> page_title("Deployments - #{product.name}")
    |> sidebar_tab(:deployments)
    |> assign(:deployments, deployments)
    |> assign(:counts, counts)
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    socket
    |> assign(:params, params)
    |> assign_deployments_with_pagination()
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

  defp assign_deployments_with_pagination(socket) do
    %{assigns: %{product: product, params: params}} = socket

    pagination_opts = Map.take(params, @pagination_opts)

    opts = %{
      page: pagination_opts["page_number"],
      page_size: pagination_opts["page_size"],
      sort: pagination_opts["sort"] || "name",
      sort_direction: pagination_opts["sort_direction"]
    }

    {entries, pager_meta} = Deployments.filter(product.id, opts)

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

    ~p"/org/#{socket.assigns.org.name}/#{socket.assigns.product.name}/deployments?#{params}"
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

  defp version(%Deployment{conditions: %{"version" => ""}}), do: "-"
  defp version(%Deployment{conditions: %{"version" => version}}), do: version

  defp tags(%Deployment{conditions: %{"tags" => tags}}), do: tags
end
