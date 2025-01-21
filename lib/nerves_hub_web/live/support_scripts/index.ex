defmodule NervesHubWeb.Live.SupportScripts.Index do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Scripts

  alias NervesHub.Repo

  alias NervesHubWeb.Components.Pager
  alias NervesHubWeb.Components.Sorting

  @pagination_opts ["page_number", "page_size", "sort", "sort_direction"]

  def mount(unsigned_params, _session, socket) do
    socket
    |> page_title("Support Scripts - #{socket.assigns.product.name}")
    |> sidebar_tab(:support_scripts)
    |> assign(:params, unsigned_params)
    |> assign_scripts_with_pagination()
    |> ok()
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
    new_params = %{sort: value}

    socket
    |> push_patch(to: self_path(socket, new_params))
    |> noreply()
  end

  def handle_event("delete-support-script", %{"script_id" => script_id}, socket) do
    authorized!(:"support_script:delete", socket.assigns.org_user)

    %{product: product} = socket.assigns

    {:ok, script} = Scripts.get(product, script_id)

    Repo.delete!(script)

    socket
    |> put_flash(:info, "Script deleted")
    |> assign(:scripts, Scripts.all_by_product(socket.assigns.product))
    |> noreply()
  end

  defp assign_scripts_with_pagination(socket) do
    %{assigns: %{product: product, params: params}} = socket

    pagination_opts = Map.take(params, @pagination_opts)

    opts = %{
      page: pagination_opts["page_number"],
      page_size: pagination_opts["page_size"],
      sort: pagination_opts["sort"],
      sort_direction: pagination_opts["sort_direction"]
    }

    {entries, pager_meta} = Scripts.filter(product.id, opts)

    socket
    |> assign(:current_sort, opts.sort)
    |> assign(:sort_direction, opts.sort_direction)
    |> assign(:scripts, entries)
    |> assign(:pager_meta, pager_meta)
  end

  defp self_path(socket, new_params) do
    current_params =
      socket.assigns.params
      |> Map.reject(fn {key, _val} -> key in ["org_name", "product_name"] end)

    params =
      stringify_keys(new_params)
      |> Enum.into(current_params)

    ~p"/org/#{socket.assigns.org.name}/#{socket.assigns.product.name}/scripts?#{params}"
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
