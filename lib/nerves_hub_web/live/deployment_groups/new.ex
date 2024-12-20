defmodule NervesHubWeb.Live.DeploymentGroup.New do
  use NervesHubWeb, :updated_live_view

  import NervesHubWeb.LayoutView

  alias NervesHub.AuditLogs
  alias NervesHub.Devices
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Tracker
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware

  alias NervesHubWeb.LayoutView.DateTimeFormat

  # @default_page 1
  # @default_page_size 25

  @default_filters %{
    connection: "",
    connection_type: "",
    firmware_version: "",
    platform: "",
    healthy: "",
    device_id: "",
    tag: "",
    updates: "",
    has_no_tags: false,
    alarm_status: "",
    alarm: "",
    metrics_key: "",
    metrics_operator: "gt",
    metrics_value: ""
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

  @filter_types %{
    connection: :string,
    connection_type: :string,
    firmware_version: :string,
    platform: :string,
    healthy: :string,
    device_id: :string,
    tag: :string,
    updates: :string,
    has_no_tags: :boolean,
    alarm_status: :string,
    alarm: :string,
    metrics_key: :string,
    metrics_operator: :string,
    metrics_value: :string
  }

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{org: org, product: product}} = socket) do
    firmware = Firmwares.get_firmwares_by_product(product.id)
    firmware_versions = Firmwares.get_firmware_versions_by_product(product.id)

    if Enum.empty?(firmware) do
      socket
      |> put_flash(
        :error,
        "You must upload a firmware version before creating a Deployment Group"
      )
      |> push_navigate(to: ~p"/org/#{org.name}/#{product.name}/firmware/upload")
      |> ok()
    else
      platforms =
        firmware
        |> Enum.map(& &1.platform)
        |> Enum.uniq()

      socket
      |> page_title("New Deployment Group - #{socket.assigns.product.name}")
      |> assign(:platforms, platforms)
      |> assign(:platform, nil)
      |> assign(:form, to_form(Ecto.Changeset.change(%DeploymentGroup{})))
      |> assign(:paginate_opts, @default_filters)
      |> assign(:total_entries, 0)
      |> assign(:selected_devices, [])
      |> assign(:current_filters, @default_filters)
      |> assign(:firmware_versions, firmware_versions)
      |> ok()
    end
  end

  def handle_params(unsigned_params, _uri, socket) do
    filters = Map.merge(@default_filters, filter_changes(unsigned_params))
    changes = pagination_changes(unsigned_params)
    pagination_opts = Map.merge(@default_pagination, changes)

    socket
    |> assign(:current_sort, Map.get(unsigned_params, "sort", "identifier"))
    |> assign(:sort_direction, Map.get(unsigned_params, "sort_direction", "asc"))
    |> assign(:current_filters, filters)
    |> assign(:paginate_opts, pagination_opts)
    |> assign(:currently_filtering, filters != @default_filters)
    |> assign(:params, unsigned_params)
    |> assign_display_devices()
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_event("select-platform", %{"deployment_group" => %{"platform" => platform}}, socket) do
    authorized!(:"deployment_group:create", socket.assigns.org_user)

    %{product: product} = socket.assigns

    firmwares = Firmwares.get_firmwares_by_product(product.id)

    firmwares =
      Enum.filter(firmwares, fn firmware ->
        firmware.platform == platform
      end)

    socket
    |> assign(:firmwares, firmwares)
    |> assign(:form, to_form(Ecto.Changeset.change(%DeploymentGroup{})))
    |> assign(:platform, platform)
    |> noreply()
  end

  # @impl Phoenix.LiveView
  def handle_event("create-deployment", %{"deployment_group" => params}, socket) do
    authorized!(:"deployment_group:create", socket.assigns.org_user)

    %{user: user, org: org, product: product} = socket.assigns

    params =
      params
      |> inject_conditions_map()
      |> whitelist([:name, :conditions, :firmware_id])
      |> Map.put(:org_id, org.id)
      |> Map.put(:is_active, false)

    org
    |> Firmwares.get_firmware(params[:firmware_id])
    |> case do
      {:ok, firmware} ->
        {firmware, ManagedDeployments.create_deployment(params)}

      {:error, :not_found} ->
        {:error, :not_found}
    end
    |> case do
      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Invalid firmware selected")
        |> noreply()

      {_, {:ok, deployment}} ->
        AuditLogs.audit!(
          user,
          deployment,
          "#{user.name} created deployment group #{deployment.name}"
        )

        socket
        |> put_flash(:info, "Deployment Group created")
        |> push_navigate(to: ~p"/org/#{org.name}/#{product.name}/deployment_groups")
        |> noreply()

      {_firmware, {:error, changeset}} ->
        socket
        |> assign(:form, to_form(changeset |> tags_to_string()))
        |> noreply()
    end
  end

  defp firmware_dropdown_options(firmwares) do
    firmwares
    |> Enum.sort_by(
      fn firmware ->
        case Version.parse(firmware.version) do
          {:ok, version} ->
            version

          :error ->
            %Version{major: 0, minor: 0, patch: 0}
        end
      end,
      {:desc, Version}
    )
    |> Enum.map(&[value: &1.id, key: firmware_display_name(&1)])
  end

  defp firmware_display_name(%Firmware{} = f) do
    "#{f.version} #{f.platform} #{f.architecture} #{f.uuid}"
  end

  defp inject_conditions_map(%{"version" => version, "tags" => tags} = params) do
    params
    |> Map.put("conditions", %{
      "version" => version,
      "tags" =>
        tags
        |> tags_as_list()
        |> MapSet.new()
        |> MapSet.to_list()
    })
  end

  defp inject_conditions_map(params), do: params

  def tags_to_string(%Ecto.Changeset{} = changeset) do
    conditions =
      changeset
      |> Ecto.Changeset.get_field(:conditions)

    tags =
      conditions
      |> Map.get("tags", [])
      |> Enum.join(",")

    conditions = Map.put(conditions, "tags", tags)

    changeset
    |> Ecto.Changeset.put_change(:conditions, conditions)
  end

  defp tags_as_list(""), do: []

  defp tags_as_list(tags) do
    tags
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  end

  # ___________________________________________________

  defp last_seen_at(connections) do
    case connections do
      [latest_connection | _] ->
        last_seen_formatted(latest_connection)

      _ ->
        ""
    end
  end

  defp last_seen_at_status(connections) do
    case connections do
      [] ->
        "Not seen yet"

      [latest_connection | _] ->
        "Last seen #{last_seen_formatted(latest_connection)}"
    end
  end

  defp last_seen_formatted(connection) do
    connection
    |> Map.get(:last_seen_at)
    |> DateTimeFormat.from_now()
  end

  defp devices_table_header(title, value, current_sort, sort_direction)
       when value == current_sort do
    caret_class = if sort_direction == "asc", do: "up", else: "down"

    assigns = %{value: value, title: title, caret_class: caret_class}

    ~H"""
    <th phx-click="sort" phx-value-sort={@value} class="pointer sort-selected">
      <%= @title %><i class={"icon-caret icon-caret-#{@caret_class}"} />
    </th>
    """
  end

  defp devices_table_header(title, value, _current_sort, _sort_direction) do
    assigns = %{value: value, title: title}

    ~H"""
    <th phx-click="sort" phx-value-sort={@value} class="pointer">
      <%= @title %>
    </th>
    """
  end

  defp firmware_update_status(device) do
    cond do
      Devices.device_in_penalty_box?(device) ->
        "firmware-penalty-box"

      device.updates_enabled == false ->
        "firmware-disabled"

      true ->
        "firmware-enabled"
    end
  end

  defp firmware_update_title(device) do
    cond do
      Devices.device_in_penalty_box?(device) ->
        "Automatic Penalty Box"

      device.updates_enabled == false ->
        "Firmware Disabled"

      true ->
        "Firmware Enabled"
    end
  end

  defp selected?(filters, field, value) do
    if filters[field] == value do
      [selected: true]
    else
      []
    end
  end

  defp assign_display_devices(
         %{assigns: %{product: product, paginate_opts: paginate_opts}} = socket
       ) do
    opts = %{
      pagination: %{page: paginate_opts.page_number, page_size: paginate_opts.page_size},
      sort:
        {String.to_existing_atom(socket.assigns.sort_direction),
         String.to_atom(socket.assigns.current_sort)},
      filters: socket.assigns.current_filters
    }

    page = Devices.filter(product.id, opts)

    statuses =
      Enum.into(page.entries, %{}, fn device ->
        socket.endpoint.subscribe("device:#{device.identifier}:internal")

        {device.identifier, Tracker.connection_status(device)}
      end)

    socket
    |> assign(:device_statuses, statuses)
    |> assign_display_devices(page)
  end

  defp assign_display_devices(%{assigns: %{paginate_opts: paginate_opts}} = socket, page) do
    paginate_opts =
      paginate_opts
      |> Map.put(:page_number, page.current_page)
      |> Map.put(:page_size, page.page_size)
      |> Map.put(:total_pages, page.total_pages)

    socket
    |> assign(:devices, page.entries)
    |> assign(:total_entries, page.total_count)
    |> assign(:paginate_opts, paginate_opts)
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

  # defp target_selected?(%{name: name}, value) when name == value, do: [selected: true]
  # defp target_selected?(_, _), do: []
end
