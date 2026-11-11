defmodule NervesHubWeb.Components.DevicePage.DetailsTab do
  use NervesHubWeb, tab_component: :details

  import Number.Delimit, only: [number_to_delimited: 2]

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.Scope
  alias NervesHub.Accounts.User.DisplayPreferences
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.DeviceEvents
  alias NervesHub.Devices
  alias NervesHub.Devices.Alarms
  alias NervesHub.Devices.Deployments
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.Metrics
  alias NervesHub.Devices.Updates
  alias NervesHub.Extensions
  alias NervesHub.Firmwares
  alias NervesHub.Helpers.RelativeTime
  alias NervesHub.ManagedDeployments
  alias NervesHub.Products
  alias NervesHub.Products.HealthProfiles
  alias NervesHub.Products.Product
  alias NervesHub.Scripts
  alias NervesHub.Scripts.Script
  alias NervesHubWeb.Components.DeviceHealth.AlarmsRow
  alias NervesHubWeb.Components.DeviceHealth.MetricLabels
  alias NervesHubWeb.Components.DeviceHealth.StatusBadge
  alias NervesHubWeb.Components.DeviceLocation
  alias NervesHubWeb.Components.DeviceNetworkIdentities
  alias NervesHubWeb.Components.UpdateProgress
  alias NervesHubWeb.Components.Utils
  alias Phoenix.Socket.Broadcast

  require Logger

  @keys_to_cleanup [
    :support_scripts,
    :selected_support_script,
    :support_script_running,
    :recently_run_support_script,
    :recently_run_support_script_output,
    :firmwares,
    :update_information,
    :alarms,
    :extension_overrides,
    :deployment_groups,
    :addable_tags
  ]

  def tab_params(_params, _uri, %{assigns: %{device: device}} = socket) do
    socket
    |> assign_support_scripts()
    |> assign(:firmwares, Firmwares.get_firmware_for_device(device))
    |> assign(:update_information, Updates.resolve_update(device))
    |> assign_health_display(device)
    |> assign(:alarms, Alarms.current_alarms_for_device(device))
    |> assign(:extension_overrides, extension_overrides(device, device.product))
    |> assign(:delta_available?, false)
    |> assign(:selected_firmware, "")
    |> assign_addable_tags()
    |> assign_metadata()
    |> assign_deployment_groups()
    |> cont()
  end

  def cleanup(), do: @keys_to_cleanup

  # The health card only renders when the extension is enabled for both the
  # product and the device, so nothing health-shaped is read otherwise — no
  # metrics, no labels, no profile resolution. An install that leaves the
  # health extension off pays none of its query load on this page.
  defp assign_health_display(socket, device) do
    if device.product.extensions.health && device.extensions.health do
      socket
      |> assign(:latest_metrics, Metrics.get_latest_metric_set(device.id))
      |> assign(:custom_labels, Products.custom_health_metrics_labels(device.product))
      |> assign(:featured_keys, featured_keys(device))
    else
      socket
      |> assign(:latest_metrics, %{})
      |> assign(:custom_labels, %{})
      |> assign(:featured_keys, nil)
    end
  end

  defp assign_metadata(%{assigns: %{device: device}} = socket) do
    metadata =
      if device.latest_connection, do: device.latest_connection.metadata || %{}, else: %{}

    entries =
      metadata
      |> Map.drop(standard_keys(device))
      |> Enum.reject(fn {_key, value} -> value in ["", nil] end)
      |> Enum.map(fn {key, value} -> {key, metadata_value(value)} end)
      |> Enum.sort_by(fn {key, _value} -> key end)

    assign(socket, :metadata_entries, entries)
  end

  # Metadata values arrive as decoded JSON, so they can be strings, numbers,
  # booleans, or nested structures. Render everything as a string so it can be
  # both displayed and copied to the clipboard.
  defp metadata_value(value) when is_binary(value), do: value
  defp metadata_value(value), do: inspect(value)

  # Values wider than the truncation cap get a hover tooltip revealing the full
  # value. The threshold roughly matches the value column's max width so short
  # values that already fit don't get a redundant tooltip.
  defp long_value?(value), do: String.length(value) > 32

  defp assign_support_scripts(%{assigns: %{product: product}} = socket) do
    scripts = Scripts.all_by_product(product)

    socket
    |> assign(:support_scripts, scripts)
    |> assign(:selected_support_script, nil)
    |> assign(:support_script_running, false)
    |> assign(:recently_run_support_script, nil)
    |> assign(:recently_run_support_script_output, nil)
  end

  # Tags already on the device are excluded so the "add tag" suggestions only
  # offer tags that can actually be added.
  defp assign_addable_tags(%{assigns: %{product: product, device: device}} = socket) do
    addable_tags = Devices.distinct_tags_for_product(product) -- (device.tags || [])
    assign(socket, :addable_tags, addable_tags)
  end

  defp assign_deployment_groups(%{assigns: %{device: %{status: :provisioned} = device}} = socket) do
    assign(socket, deployment_groups: ManagedDeployments.eligible_deployment_groups(device))
  end

  defp assign_deployment_groups(%{assigns: %{product: product}} = socket) do
    assign(socket,
      deployment_groups: ManagedDeployments.get_deployment_groups_by_product(product)
    )
  end

  def render(assigns) do
    ~H"""
    <div
      id="details-tab"
      phx-mounted={JS.remove_class("opacity-0")}
      class="tab-content flex flex-col gap-4 p-4 opacity-0 transition-all duration-500 sm:p-6 md:flex-row md:items-start md:justify-between phx-click-loading:opacity-50"
    >
      <div
        :for={{column, boxes} <- details_columns(@user, @product, @device)}
        id={"device-details-#{column}"}
        phx-hook="DeviceDetailsLayout"
        data-column={column}
        class="flex min-h-24 w-full min-w-0 flex-col gap-4 md:w-1/2"
      >
        <div :for={box <- boxes} :key={box} id={"device-details-box-#{box}"} data-box={box} class="group/box relative">
          <span
            data-drag-handle
            title="Drag to move"
            class="absolute top-4.25 left-0.5 z-10 lucide-grip-vertical--bold size-3.5 cursor-grab text-content-faint opacity-0 transition-opacity group-hover/box:opacity-100 active:cursor-grabbing"
          />
          <.health_box
            :if={box == :health}
            product={@product}
            device={@device}
            latest_metrics={@latest_metrics}
            custom_labels={@custom_labels}
            featured_keys={@featured_keys}
            device_connection={@device_connection}
            alarms={@alarms}
          />
          <.general_info
            :if={box == :general_info}
            current_scope={@current_scope}
            device={@device}
            addable_tags={@addable_tags}
            metadata_entries={@metadata_entries}
            extension_overrides={@extension_overrides}
          />
          <.deployment_box
            :if={box == :deployment}
            current_scope={@current_scope}
            org={@org}
            product={@product}
            device={@device}
            device_connection={@device_connection}
            deployment_groups={@deployment_groups}
            update_information={@update_information}
            firmwares={@firmwares}
            selected_firmware={@selected_firmware}
            delta_available?={@delta_available?}
            stage={@firmware_update_stage}
            progress={@firmware_update_progress}
            inflight_version={@inflight_version}
            inflight_started_at={@inflight_started_at}
            inflight_firmware_uuid={@inflight_firmware_uuid}
          />
          <.location_box
            :if={box == :location}
            current_scope={@current_scope}
            device={@device}
            enable_location_editor={!!assigns[:enable_location_editor]}
            map_style={DisplayPreferences.map_style(@user.display_preferences)}
          />
          <.network_identities_box :if={box == :network_identities} product={@product} device={@device} />
          <.support_scripts_box
            :if={box == :support_scripts}
            device_connection={@device_connection}
            support_scripts={@support_scripts}
            selected_support_script={@selected_support_script}
            support_script_running={@support_script_running}
            recently_run_support_script={@recently_run_support_script}
            recently_run_support_script_output={@recently_run_support_script_output}
          />
        </div>
      </div>
    </div>
    """
  end

  def hooked_event("set-update-mode", %{"mode" => mode}, socket) do
    %{current_scope: scope, device: device} = socket.assigns

    authorized!(:"device:toggle-updates", scope)

    mode = String.to_existing_atom(mode)

    case Updates.set_update_mode(device, mode, scope.user) do
      {:ok, updated_device} ->
        socket
        |> assign(:device, updated_device)
        |> assign(:update_information, Updates.resolve_update(updated_device))
        |> put_flash(:info, "Firmware updates set to #{update_mode_label(mode)}.")
        |> halt()

      _error ->
        socket
        |> put_flash(
          :error,
          "We couldn't change how this device receives updates. Please contact support if this happens again."
        )
        |> halt()
    end
  end

  def hooked_event("clear-manual-location-information", _, socket) do
    authorized!(:"device:update", socket.assigns.current_scope)

    {:ok, device} =
      Devices.update_device(socket.assigns.device, %{
        custom_location_coordinates: nil
      })

    socket
    |> assign(:device, device)
    |> put_flash(:info, "Manual device location information has been cleared.")
    |> halt()
  end

  def hooked_event("enable-location-editor", _, socket) do
    socket
    |> assign(:enable_location_editor, true)
    |> put_flash(:info, "Please use the map to search and pin your devices location.")
    |> halt()
  end

  def hooked_event("discard-location-changes", _, socket) do
    socket
    |> assign(:enable_location_editor, false)
    |> halt()
  end

  # Sent by the location box's map style menu. An empty style goes back to
  # following the theme.
  def hooked_event("set-map-style", %{"style" => style}, socket) do
    %{user: user, current_scope: scope} = socket.assigns

    case Accounts.update_user_map_style(user, style) do
      {:ok, user} ->
        socket
        |> assign(:user, user)
        |> assign(:current_scope, %{scope | user: user})
        |> halt()

      {:error, _changeset} ->
        socket
        |> put_flash(:error, "Your map style couldn't be saved. Please reload the page and try again.")
        |> halt()
    end
  end

  def hooked_event("update-device-location", latlng, socket) do
    socket
    |> assign(:buffer_custom_location, latlng)
    |> halt()
  end

  def hooked_event("save-location-changes", _, socket) do
    authorized!(:"device:update", socket.assigns.current_scope)

    {:ok, device} =
      Devices.update_device(socket.assigns.device, %{
        custom_location_coordinates: [
          socket.assigns.buffer_custom_location["lat"],
          socket.assigns.buffer_custom_location["lng"]
        ]
      })

    socket
    |> assign(:device, device)
    |> put_flash(:info, "Custom location coordinates saved.")
    |> assign(:enable_location_editor, false)
    |> halt()
  end

  def hooked_event("set-deployment-group", %{"deployment_id" => ""}, socket) do
    socket
    |> put_flash(:error, "Please select a deployment group.")
    |> halt()
  end

  def hooked_event("set-deployment-group", %{"deployment_id" => deployment_id}, socket) do
    %{user: user, device: device, deployment_groups: deployment_groups} = socket.assigns

    authorized!(:"device:set-deployment-group", socket.assigns.current_scope)

    deployment = Enum.find(deployment_groups, &(&1.id == String.to_integer(deployment_id)))
    device = Deployments.update_deployment_group(device, deployment)
    _ = DeviceTemplates.audit_device_deployment_group_update(user, device, deployment)

    send(self(), :reload_device)

    socket
    |> assign(:device, device)
    |> put_flash(:info, "Device successfully added to Deployment Group.")
    |> halt()
  end

  def hooked_event("push-available-update", _, socket) do
    authorized!(:"device:push-update", socket.assigns.current_scope)

    %{device: device, user: user} = socket.assigns

    case DeviceEvents.schedule_update(device.id, device.deployment_group, user: user) do
      {:ok, _inflight_update} ->
        socket
        |> put_flash(:info, "Pushing available firmware update.")
        |> halt()

      {:error, :already_updating} ->
        already_updating_error(socket)
    end
  end

  def hooked_event("select-firmware-version", %{"uuid" => ""}, socket) do
    socket
    |> halt()
  end

  def hooked_event("select-firmware-version", %{"uuid" => uuid}, socket) do
    %{product: product, device: device} = socket.assigns

    case Firmwares.get_firmware_by_product_and_uuid(product, uuid) do
      {:error, :not_found} ->
        unavailable_firmware_error(socket)

      {:ok, firmware} ->
        firmware_delta_updatable? = Firmwares.delta_updatable?(device, firmware)
        delta_complete? = Firmwares.delta_ready?(device, firmware)

        socket
        |> assign(:delta_available?, firmware_delta_updatable? && delta_complete?)
        |> assign(:selected_firmware, uuid)
        |> halt()
    end
  end

  def hooked_event("push-update", %{"uuid" => uuid}, socket) when uuid == "" do
    socket
    |> put_flash(:error, "Please select a firmware version to send to the device.")
    |> halt()
  end

  def hooked_event("push-update", %{"uuid" => uuid}, socket) do
    authorized!(:"device:push-update", socket.assigns.current_scope)

    %{product: product, device: device, user: user, org: org} = socket.assigns

    case Firmwares.get_firmware_by_product_and_uuid(product, uuid) do
      {:error, :not_found} ->
        unavailable_firmware_error(socket)

      {:ok, firmware} ->
        Logger.info("Manually sending full firmware",
          firmware_uuid: firmware.uuid,
          device_identifier: device.identifier
        )

        opts =
          if proxy_url = get_in(org.settings.firmware_proxy_url) do
            [firmware_proxy_url: proxy_url]
          else
            []
          end

        case DeviceEvents.manual_update(device, firmware, user, opts) do
          {:ok, device} ->
            socket
            |> assign(:device, device)
            |> put_flash(:info, "Firmware update request requested.")
            |> halt()

          {:error, :already_updating} ->
            already_updating_error(socket)
        end
    end
  end

  def hooked_event("push-delta", %{"uuid" => uuid}, socket) when uuid == "" do
    socket
    |> put_flash(:error, "Please select a firmware version to send to the device.")
    |> halt()
  end

  def hooked_event("push-delta", %{"uuid" => uuid}, socket) do
    authorized!(:"device:push-update", socket.assigns.current_scope)

    %{product: product, device: device, user: user, org: org} = socket.assigns

    case Firmwares.get_firmware_by_product_and_uuid(product, uuid) do
      {:error, :not_found} ->
        unavailable_firmware_error(socket)

      {:ok, firmware} ->
        Logger.info(
          "Manually sending firmware delta",
          source_uuid: device.firmware_metadata.uuid,
          target_uuid: firmware.uuid,
          device_identifier: device.identifier
        )

        opts =
          if proxy_url = get_in(org.settings.firmware_proxy_url) do
            [firmware_proxy_url: proxy_url]
          else
            []
          end

        case DeviceEvents.manual_update(device, firmware, user, opts ++ [delta: true]) do
          {:ok, device} ->
            socket
            |> assign(:device, device)
            |> put_flash(:info, "Sending firmware update request.")
            |> halt()

          {:error, :already_updating} ->
            already_updating_error(socket)
        end
    end
  end

  def hooked_event("remove-from-deployment-group", _, %{assigns: %{device: device}} = socket) do
    authorized!(:"device:set-deployment-group", socket.assigns.current_scope)

    device = Deployments.clear_deployment_group(device)

    send(self(), :reload_device)

    socket
    |> assign(:device, device)
    |> put_flash(:info, "Device successfully removed from the deployment group")
    |> halt()
  end

  def hooked_event("select-script", %{"script_id" => ""}, socket) do
    socket
    |> assign(:selected_support_script, nil)
    |> halt()
  end

  def hooked_event("select-script", %{"script_id" => id}, %{assigns: %{support_scripts: scripts}} = socket) do
    script = Enum.find(scripts, fn script -> script.id == String.to_integer(id) end)

    socket
    |> assign(:selected_support_script, script)
    |> halt()
  end

  def hooked_event("run-script", _params, socket) do
    %{assigns: %{device: device, selected_support_script: script, current_scope: scope}} = socket

    authorized!(:"support_script:run", scope)

    socket
    |> start_async(:run_script, fn -> Scripts.Runner.send(device, script) end)
    |> assign(:support_script_running, true)
    |> assign(:recently_run_support_script, script)
    |> assign(:recently_run_support_script_output, nil)
    |> halt()
  end

  def hooked_event("clear-script-output", _params, socket) do
    socket
    |> assign(:support_script_running, false)
    |> assign(:recently_run_support_script, nil)
    |> assign(:recently_run_support_script_output, nil)
    |> halt()
  end

  def hooked_event("add-tag", %{"tag" => tag}, socket) do
    authorized!(:"device:update", socket.assigns.current_scope)

    Devices.add_tag(socket.assigns.device, socket.assigns.user, tag)
    |> case do
      {:ok, device} ->
        socket
        |> assign(:device, device)
        |> assign_addable_tags()
        |> put_flash(:info, "Tag \"#{tag}\" added successfully.")
        |> halt()

      {:error, msg} ->
        socket
        |> put_flash(:error, "Failed to add tag: #{msg}")
        |> halt()
    end
  end

  def hooked_event("remove-tag", %{"tag" => tag}, socket) do
    authorized!(:"device:update", socket.assigns.current_scope)

    Devices.remove_tag(socket.assigns.device, socket.assigns.user, tag)
    |> case do
      {:ok, device} ->
        socket
        |> assign(:device, device)
        |> assign_addable_tags()
        |> put_flash(:info, "Tag \"#{tag}\" removed successfully.")
        |> halt()

      {:error, _, _, _} ->
        socket
        |> put_flash(:error, "There was an error removing the tag, if this persists, please contact support.")
        |> halt()
    end
  end

  # Sent by the DeviceDetailsLayout hook after a box is dropped, with each
  # column's boxes top to bottom as they now appear on the page.
  def hooked_event("arrange-device-details", %{"left" => left, "right" => right}, socket)
      when is_list(left) and is_list(right) do
    %{user: user, product: product, device: device, current_scope: scope} = socket.assigns

    hidden = Enum.reject(DisplayPreferences.device_details_boxes(), &box_visible?(&1, product, device))
    current = DisplayPreferences.device_details_layout(user.display_preferences)
    {left, right} = restore_hidden_boxes({to_boxes(left), to_boxes(right)}, current, hidden)

    case Accounts.update_user_device_details_layout(user, left, right) do
      {:ok, user} ->
        socket
        |> assign(:user, user)
        |> assign(:current_scope, %{scope | user: user})
        |> halt()

      {:error, _changeset} ->
        socket
        |> put_flash(:error, "Your layout couldn't be saved. Please reload the page and try again.")
        |> halt()
    end
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  def hooked_info(:platform_or_architecture_updated, %{assigns: %{device: device}} = socket) do
    assign(socket, :firmwares, Firmwares.get_firmware_for_device(device))
    |> halt()
  end

  def hooked_info(
        %Broadcast{topic: "product:" <> _product_id, event: "firmware/created", payload: %{firmware: new_firmware}},
        socket
      ) do
    firmware = Firmwares.get_firmware_for_device(socket.assigns.device)

    socket
    |> assign(:firmwares, firmware)
    |> put_flash(
      :notice,
      "New firmware #{new_firmware.version} (#{String.slice(new_firmware.uuid, 0..7)}) is available for selection"
    )
    |> halt()
  end

  def hooked_info(
        %Broadcast{topic: "product:" <> _product_id, event: "firmware/deleted", payload: %{firmware: deleted_firmware}},
        socket
      ) do
    firmware = Firmwares.get_firmware_for_device(socket.assigns.device)

    socket
    |> assign(:firmwares, firmware)
    |> put_flash(
      :notice,
      "Firmware #{deleted_firmware.version} (#{String.slice(deleted_firmware.uuid, 0..7)}) has been deleted by another user."
    )
    |> halt()
  end

  def hooked_info(%Broadcast{event: "health_check_report"}, %{assigns: %{device: device}} = socket) do
    latest_metrics = Metrics.get_latest_metric_set(device.id)

    socket
    |> assign(:latest_metrics, latest_metrics)
    |> assign_metadata()
    |> halt()
  end

  # Sent by `NervesHub.Devices.Alarms` whenever the device's raised set moves,
  # whichever extension moved it.
  def hooked_info(%Broadcast{event: "alarms:updated"}, %{assigns: %{device: device}} = socket) do
    socket
    |> assign(:alarms, Alarms.current_alarms_for_device(device))
    |> halt()
  end

  def hooked_info(_event, socket), do: {:cont, socket}

  def hooked_async(:run_script, result, socket) do
    output =
      case result do
        {:ok, {:ok, output}} ->
          output

        {:ok, {:error, reason}} ->
          "Error: #{reason}"

        e ->
          inspect(e)
      end

    socket
    |> assign(:support_script_running, false)
    |> assign(:recently_run_support_script_output, output)
    |> halt()
  end

  # TODO: this is duplicated code, find a new way to reuse it
  defp disconnected?(connection) do
    is_nil(connection) || connection.status != :connected
  end

  defp extension_overrides(device, product) do
    device.extensions
    |> Map.from_struct()
    |> Enum.filter(fn {extension, enabled} ->
      enabled == false and product.extensions[extension]
    end)
    |> Enum.map(&elem(&1, 0))
  end

  # The boxes in each column, top to bottom, as the user arranged them. Boxes
  # with nothing to show are left out: the map when geo is off, and the old
  # alarms box, which is now a row in the Health card.
  defp details_columns(user, product, device) do
    preferences = user.display_preferences
    visible? = &box_visible?(&1, product, device)

    {left, right} = DisplayPreferences.device_details_layout(preferences)
    left = Enum.filter(left, visible?)
    right = Enum.filter(right, visible?)

    # Without the map the right column would open with the smaller boxes, so
    # the default layout moves General Info up into its place. A layout the
    # user arranged stays as they arranged it.
    if DisplayPreferences.custom_device_details_layout?(preferences) or visible?.(:location) do
      [left: left, right: right]
    else
      [left: List.delete(left, :general_info), right: [:general_info | List.delete(right, :general_info)]]
    end
  end

  defp box_visible?(:location, product, device), do: show_location?(product, device)
  # Alarms are a row in the Health card now. A layout saved with an alarms
  # box keeps its place for it, but nothing is drawn there.
  defp box_visible?(:alarms, _product, _device), do: false
  defp box_visible?(_box, _product, _device), do: true

  # Box names come from the page, so only known ones are turned into atoms.
  defp to_boxes(names) do
    known = Map.new(DisplayPreferences.device_details_boxes(), &{Atom.to_string(&1), &1})
    Enum.flat_map(names, &List.wrap(known[&1]))
  end

  # A hidden box isn't on the page to be dragged, so it goes back to where it
  # was in the layout being replaced. Each column is restored from the top
  # down: an insert shifts every box below it, so a box can only go back once
  # the boxes above it are in place.
  defp restore_hidden_boxes({left, right}, {old_left, old_right}, hidden) do
    restore = fn column, old_column ->
      old_column
      |> Enum.with_index()
      |> Enum.filter(fn {box, _index} -> box in hidden end)
      |> Enum.reduce(column -- hidden, fn {box, index}, column -> List.insert_at(column, index, box) end)
    end

    {restore.(left, old_left), restore.(right, old_right)}
  end

  # The map is left out entirely, rather than shown as a placeholder, when geo
  # is switched off for the product or the device, or when the platform has no
  # Mapbox token to draw it with.
  defp show_location?(product, device) do
    product.extensions.geo and device.extensions.geo and
      not is_nil(Application.get_env(:nerves_hub, :mapbox_access_token))
  end

  defp extract_location_data(%{custom_location_coordinates: coordinates}) when not is_nil(coordinates) do
    %{
      "latitude" => List.first(coordinates),
      "longitude" => List.last(coordinates),
      "source" => "manual"
    }
  end

  defp extract_location_data(%Device{latest_connection: connection}) when not is_nil(connection) do
    connection.metadata["location"]
  end

  defp extract_location_data(_), do: %{}

  defp standard_keys(%{firmware_metadata: nil}), do: []

  defp standard_keys(%{firmware_metadata: firmware_metadata}),
    do: firmware_metadata |> Map.keys() |> Enum.map(&to_string/1)

  # Alarms reach the platform through either extension, so the card shows if
  # either is on for this device.
  defp alarms_reported?(product, device) do
    Enum.any?([:health, :alarms], &(product.extensions[&1] and device.extensions[&1]))
  end

  defp update_mode_label(:automatic), do: "automatic"
  defp update_mode_label(:device_managed), do: "device managed"
  defp update_mode_label(:off), do: "off"

  defp featured_keys(device) do
    HealthProfiles.featured_keys(device)
  end

  @gauge_order [:cpu, :memory, :disk, :load]

  # A gauge per featured metric of the device's health profile. Keys the
  # composite gauges cover collapse into their gauge (featuring
  # cpu_usage_percent or cpu_temp gives the CPU gauge) and any other featured
  # key gets a plain value gauge. An engaged metric with no gauge of its own
  # is added after these. With no profile, the pre-profile fixed trio.
  # Composite gauges come in the Health tab's order, CPU, memory, disk and
  # load, whatever order the profile lists their keys in.
  defp featured_tiles(nil), do: [:cpu, :memory, :load]

  defp featured_tiles(featured_keys) do
    featured_keys
    |> Enum.map(&tile_for/1)
    |> Enum.uniq()
    |> Enum.sort_by(&(Enum.find_index(@gauge_order, fn tile -> tile == &1 end) || length(@gauge_order)))
  end

  # The frame every box on the tab shares, and the header row across its top.
  attr(:id, :string, default: nil)
  attr(:class, :any, default: nil)
  slot(:inner_block, required: true)

  defp card(assigns) do
    ~H"""
    <section id={@id} class={["flex flex-col rounded-card border border-line-default bg-surface-raised shadow-card", @class]}>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr(:title, :string, required: true)
  slot(:inner_block, doc: "beside the title")
  slot(:aside, doc: "at the end of the row")

  defp card_header(assigns) do
    ~H"""
    <div class="flex h-12 shrink-0 items-center justify-between gap-3 px-4">
      <div class="flex min-w-0 items-center gap-2.5">
        <h2 class="text-sm/4.5 font-semibold text-content-strong">{@title}</h2>
        {render_slot(@inner_block)}
      </div>
      <div :if={@aside != []} class="flex shrink-0 items-center gap-2.5 text-xs text-content-faint">
        {render_slot(@aside)}
      </div>
    </div>
    """
  end

  # A label and its value on a line, with a hairline above. Rows stack inside
  # a `px-4` wrapper so the rules stop short of the card's edges.
  attr(:label, :string, required: true)
  attr(:class, :any, default: nil)
  slot(:inner_block, required: true)

  defp info_row(assigns) do
    ~H"""
    <div class={["flex min-h-10 items-center gap-3 border-t border-line-subtle py-2", @class]}>
      <span class="w-26 shrink-0 text-ui/4 text-content-muted sm:w-37">{@label}</span>
      <div class="flex min-w-0 flex-1 flex-wrap items-center gap-x-2 gap-y-1 text-ui/4">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr(:product, Product, required: true)
  attr(:device, Device, required: true)
  attr(:device_connection, :any)
  attr(:latest_metrics, :map, required: true)
  attr(:custom_labels, :map, required: true)
  attr(:featured_keys, :any)
  attr(:alarms, :any)

  defp health_box(assigns) do
    ~H"""
    <.card :if={!@product.extensions.health || !@device.extensions.health} id="health-card">
      <.card_header title="Health" />
      <p class="px-4 pb-4 text-ui/4.5 text-content-muted">
        Reporting is not enabled {if(!@product.extensions.health, do: "for your product", else: "for your device")}.
        <.link class="underline decoration-line-strong underline-offset-4 hover:text-content-strong" href={health_docs()}>
          Learn more about device health and alert reporting.
        </.link>
      </p>
      <AlarmsRow.render :if={alarms_reported?(@product, @device)} id="alarms" alarms={@alarms} />
    </.card>

    <.card :if={Enum.empty?(@latest_metrics) && @product.extensions.health && @device.extensions.health} id="health-card">
      <.card_header title="Health" />
      <p class="px-4 pb-4 text-ui/4.5 text-content-muted">
        No device health information has been received.
        <.link class="underline decoration-line-strong underline-offset-4 hover:text-content-strong" href={health_docs()}>
          Learn more about device health reporting.
        </.link>
      </p>
      <AlarmsRow.render :if={alarms_reported?(@product, @device)} id="alarms" alarms={@alarms} />
    </.card>

    <.card :if={Enum.any?(@latest_metrics) && @product.extensions.health && @device.extensions.health} id="health-card">
      <.card_header title="Health">
        <StatusBadge.render health={@device.latest_health} stale?={disconnected?(@device_connection)} />
        <:aside>
          <span>
            {if disconnected?(@device_connection), do: "Last reported", else: "Updated"}
            <time id="health-last-updated" phx-hook="UpdatingTimeAgo" datetime={String.replace(DateTime.to_string(DateTime.truncate(@latest_metrics["timestamp"], :second)), " ", "T")}>
              {RelativeTime.from_now(@latest_metrics["timestamp"])}
            </time>
          </span>
          <.link href={health_docs()} title="Learn more about device health reporting" aria-label="Learn more about device health reporting" class="flex text-content-faint hover:text-content-strong">
            <span class="lucide-circle-question-mark size-3.75" aria-hidden="true"></span>
          </.link>
        </:aside>
      </.card_header>

      <div class="grid grid-cols-[repeat(auto-fill,minmax(9.5rem,1fr))] items-start gap-x-7 gap-y-4 px-4 pt-1 pb-4.5">
        <.gauge
          :for={tile <- featured_tiles(@featured_keys)}
          tile={tile}
          latest_metrics={@latest_metrics}
          custom_labels={@custom_labels}
          engaged={engaged_for(tile, StatusBadge.engaged_reasons(@device.latest_health))}
        />
        <.gauge
          :for={{level, key, reason} <- uncovered_reasons(@device.latest_health, @featured_keys)}
          tile={{:metric, key}}
          latest_metrics={@latest_metrics}
          custom_labels={@custom_labels}
          engaged={{level, reason}}
        />
      </div>

      <AlarmsRow.render :if={alarms_reported?(@product, @device)} id="alarms" alarms={@alarms} />
    </.card>
    """
  end

  attr(:org, Org, required: true)
  attr(:product, Product, required: true)
  attr(:current_scope, Scope, required: true)
  attr(:device, Device, required: true)
  attr(:device_connection, :any)
  attr(:deployment_groups, :list, required: true)
  attr(:update_information, :map, required: true)
  attr(:firmwares, :list, required: true)
  attr(:selected_firmware, :string, required: true)
  attr(:delta_available?, :boolean, required: true)
  attr(:stage, :string, default: nil, doc: "the in-flight update's stage, nil without one")
  attr(:progress, :any, default: nil)
  attr(:inflight_version, :string, default: nil)
  attr(:inflight_started_at, :any, default: nil)
  attr(:inflight_firmware_uuid, :string, default: nil)

  defp deployment_box(assigns) do
    assigns =
      assign(
        assigns,
        :installing_release?,
        installing_release?(assigns.device, assigns.stage, assigns.inflight_firmware_uuid)
      )

    ~H"""
    <.card id="firmware-updates-card">
      <.card_header title="Firmware updates" />

      <.updating_panel
        :if={UpdateProgress.updating?(@stage)}
        stage={@stage}
        progress={@progress}
        version={@inflight_version}
        started_at={@inflight_started_at}
      />

      <div class="flex flex-col px-4 pb-1.5">
        <.info_row label="Deployment group">
          <%= cond do %>
            <% @device.deployment_group -> %>
              <.link
                navigate={~p"/org/#{@org}/#{@product}/deployment_groups/#{@device.deployment_group}"}
                class="-mb-1 min-w-0 flex-1 truncate pb-1 font-medium text-content-strong underline decoration-line-strong underline-offset-4 hover:decoration-content-muted"
              >
                {@device.deployment_group.name}
              </.link>
              <button
                :if={authorized?(:"device:set-deployment-group", @current_scope)}
                type="button"
                class="cursor-pointer text-xs font-medium text-content-muted hover:text-alert-content"
                data-confirm="Are you sure you want to remove the device from the deployment?"
                aria-label="Remove device from the assigned deployment group"
                phx-click="remove-from-deployment-group"
              >
                Remove…
              </button>
            <% Enum.empty?(@deployment_groups) -> %>
              <span class="text-content-muted">No deployment groups match the device's platform and architecture.</span>
            <% true -> %>
              <form id="set-deployment-group-form" phx-update="ignore" phx-submit="set-deployment-group" class="flex w-full items-center gap-2">
                <label for="deployment_group" class="sr-only">Deployment group</label>
                <.select_control id="deployment_group" name="deployment_id">
                  <option value="">Select a deployment group</option>
                  <option :for={deployment_group <- @deployment_groups} value={deployment_group.id}>
                    {deployment_group.name} - ({deployment_group.current_release.firmware.platform}, {deployment_group.current_release.firmware.architecture})
                  </option>
                </.select_control>
                <.button type="submit" aria-label="Assign to deployment" data-confirm="Are you sure you want to add the device to the deployment group?">
                  Assign
                </.button>
              </form>
          <% end %>
        </.info_row>

        <.info_row :if={@device.deployment_group && @device.deployment_group.current_release} label="Group release">
          <span class="font-mono text-xs font-semibold text-content-strong">{@device.deployment_group.current_release.firmware.version}</span>
          <span :if={@installing_release?} class="text-xs font-medium text-notice-content">Installing on this device now</span>
          <span :if={!@installing_release? && !@update_information.update_available} class="flex items-center gap-1 text-xs font-medium text-success-content">
            <span class="lucide-check--bold size-3.25" aria-hidden="true"></span>Device is up to date
          </span>
          <span :if={!@installing_release? && @update_information.update_available} class="text-xs font-medium text-notice-content">Update available</span>
          <.button
            :if={!@installing_release? && @update_information.update_available}
            size="sm"
            class="ml-auto"
            phx-click="push-available-update"
            aria-label="Send available update"
            data-confirm="Are you sure you want to skip the queue?"
            disabled={disconnected?(@device_connection)}
          >
            Skip the queue
          </.button>
        </.info_row>

        <p :if={@device.status == :registered && @device.deployment_id} class="border-t border-line-subtle py-2.5 text-xs text-content-muted">
          The device will be removed from the deployment group when it connects if its architecture and platform don't match.
        </p>
      </div>

      <div :if={Enum.any?(@firmwares)} class="flex flex-col gap-2 rounded-b-card border-t border-line-default bg-surface-muted px-4 pt-3.5 pb-4">
        <span class="text-xs font-medium text-content-muted">Send a specific version, outside the deployment group</span>
        <form id="push-update-form" phx-change="select-firmware-version" class="flex w-full items-center gap-2">
          <label for="firmware" class="sr-only">Firmware</label>
          <.select_control id="firmware" name="uuid">
            <option value="">Select a version</option>
            <option :for={firmware <- @firmwares} value={firmware.uuid} selected={@selected_firmware && firmware.uuid == @selected_firmware}>
              {firmware.version} ({String.slice(firmware.uuid, 0..7)})
            </option>
          </.select_control>

          <.button
            :if={@delta_available?}
            type="button"
            disabled={disconnected?(@device_connection)}
            aria-label="Send delta firmware update"
            data-confirm="Are you sure you want to send this delta firmware to the device?"
            phx-value-uuid={@selected_firmware}
            phx-click="push-delta"
          >
            Send delta update
          </.button>
          <.button
            type="button"
            disabled={disconnected?(@device_connection)}
            aria-label="Send firmware update"
            data-confirm="Are you sure you want to send this firmware to the device?"
            phx-value-uuid={@selected_firmware}
            phx-click="push-update"
          >
            {if @delta_available?, do: "Send full update", else: "Send update…"}
          </.button>
        </form>
      </div>
    </.card>
    """
  end

  attr(:stage, :string, required: true)
  attr(:progress, :any, required: true)
  attr(:version, :string, required: true)
  attr(:started_at, :any, required: true)

  # The update the device is part way through, from the request being sent to
  # the reboot that finishes it.
  defp updating_panel(assigns) do
    assigns = assign(assigns, :percent, UpdateProgress.percent(assigns.stage, assigns.progress))

    ~H"""
    <div class="flex px-4 pb-1">
      <div id="updating-panel" class="flex flex-1 flex-col gap-2 rounded bg-notice-soft px-3.5 py-3 text-xs">
        <div class="flex items-center justify-between gap-3">
          <div class="flex min-w-0 items-center gap-2">
            <span class="lucide-download size-3.75 text-notice-content" aria-hidden="true"></span>
            <span class="truncate font-mono text-ui/4 font-semibold text-content-strong">
              {if @version, do: "Updating to #{@version}", else: "Updating firmware"}
            </span>
          </div>
          <span class="shrink-0 font-medium text-notice-content">{UpdateProgress.phase(@stage, @progress)}</span>
        </div>
        <div
          class="flex h-1 rounded-full bg-white/10 light:bg-white/70"
          role="progressbar"
          aria-label="Update progress"
          aria-valuemin="0"
          aria-valuemax="100"
          aria-valuenow={@percent}
        >
          <div class="h-1 rounded-full bg-primary-hover transition-[width] light:bg-indigo-600" style={"width: #{@percent}%"}></div>
        </div>
        <div class="flex justify-between gap-3 text-content-muted">
          <span :if={@started_at}>{if @stage == "requested", do: "Sent", else: "Started"} {RelativeTime.from_now(@started_at)}</span>
          <span class="ml-auto">{UpdateProgress.next_step(@stage)}</span>
        </div>
      </div>
    </div>
    """
  end

  # Whether the update under way is the deployment group's release.
  defp installing_release?(%{deployment_group: %{current_release: %{firmware: %{uuid: uuid}}}}, stage, uuid),
    do: UpdateProgress.updating?(stage)

  defp installing_release?(_device, _stage, _inflight_firmware_uuid), do: false

  # A native select drawn as the design's control: the chevron is ours, so
  # the browser's arrow and the forms plugin's background chevron are both
  # turned off, as is the plugin's vertical padding, which would clip the
  # text at this height.
  attr(:id, :string, required: true)
  attr(:name, :string, required: true)
  slot(:inner_block, required: true)

  defp select_control(assigns) do
    ~H"""
    <div class="grid min-w-0 grow grid-cols-1">
      <select
        id={@id}
        name={@name}
        class="col-start-1 row-start-1 h-8.5 min-w-0 cursor-pointer appearance-none rounded border border-line-control border-b-line-strong bg-surface-raised bg-none py-0 pr-8 pl-3 text-ui text-content-body focus:outline focus:-outline-offset-1 focus:outline-focus-ring"
      >
        {render_slot(@inner_block)}
      </select>
      <span class="pointer-events-none col-start-1 row-start-1 mr-2.5 lucide-chevron-down size-3.5 self-center justify-self-end text-content-faint" aria-hidden="true"></span>
    </div>
    """
  end

  attr(:current_scope, Scope, required: true)
  attr(:device, Device, required: true)
  attr(:enable_location_editor, :boolean, required: true)
  attr(:map_style, :atom, required: true)

  defp location_box(assigns) do
    ~H"""
    <.card id="location-card" class="overflow-clip">
      <DeviceLocation.render
        location={extract_location_data(@device)}
        enable_location_editor={@enable_location_editor}
        map_style={@map_style}
        editable={authorized?(:"device:update", @current_scope)}
      />
    </.card>
    """
  end

  attr(:product, Product, required: true)
  attr(:device, Device, required: true)

  defp network_identities_box(assigns) do
    ~H"""
    <.card id="network-identities-card">
      <DeviceNetworkIdentities.render
        enabled_product={@product.extensions.network_identity}
        enabled_device={@device.extensions.network_identity}
        identities={@device.network_identities}
      />
    </.card>
    """
  end

  attr(:device_connection, :any)
  attr(:support_scripts, :list, required: true)
  attr(:selected_support_script, :any)
  attr(:support_script_running, :boolean, required: true)
  attr(:recently_run_support_script, :any)
  attr(:recently_run_support_script_output, :any)

  defp support_scripts_box(assigns) do
    ~H"""
    <.card id="support-scripts-card">
      <.card_header title="Support scripts">
        <:aside>
          <span :if={Enum.any?(@support_scripts) && disconnected?(@device_connection)}>Runs when the device is online</span>
          <span :if={Enum.any?(@support_scripts) && !disconnected?(@device_connection)}>{length(@support_scripts)} available</span>
        </:aside>
      </.card_header>

      <p :if={Enum.empty?(@support_scripts)} class="px-4 pb-4 text-ui/4.5 text-content-muted">No support scripts have been configured.</p>

      <% searchable_scripts? = length(@support_scripts) > 10 %>
      <div :if={Enum.any?(@support_scripts)} class="flex flex-col gap-3 px-4 pb-4">
        <div class="flex w-full items-center gap-2">
          <form :if={!searchable_scripts?} id="run-script-form" phx-change="select-script" class="flex min-w-0 grow">
            <label for="script_id" class="sr-only">Support script</label>
            <.select_control id="script_id" name="script_id">
              <option value="" selected={is_nil(@selected_support_script)}>Select a support script</option>
              <option :for={script <- @support_scripts} value={script.id} selected={@selected_support_script && script.id == @selected_support_script.id}>
                {script.name} ({Script.language_label(script.language)})
              </option>
            </.select_control>
          </form>

          <div
            :if={searchable_scripts?}
            id="script-autocomplete"
            class="relative grow"
            phx-hook="ScriptAutocomplete"
            data-scripts={Jason.encode!(Enum.map(@support_scripts, &%{id: &1.id, name: &1.name, language: Script.language_label(&1.language)}))}
            data-selected-id={@selected_support_script && @selected_support_script.id}
          >
            <label for="script_search" class="sr-only">Search support scripts</label>
            <input
              type="text"
              id="script_search"
              data-script-search
              autocomplete="off"
              placeholder="Search scripts…"
              value={@selected_support_script && @selected_support_script.name}
              class="h-8.5 w-full rounded border border-line-control border-b-line-strong bg-surface-raised px-3 text-ui text-content-body placeholder:text-content-muted focus:outline focus:-outline-offset-1 focus:outline-focus-ring"
            />
            <ul
              id="script_search-suggestions"
              data-script-suggestions
              phx-update="ignore"
              role="listbox"
              hidden
              class="absolute z-10 mt-1 max-h-56 w-full overflow-y-auto rounded-md border border-line-default bg-surface-overlay py-1 shadow-overlay"
            >
            </ul>
          </div>

          <.button
            type="button"
            aria-label="Run support script"
            phx-click="run-script"
            phx-value-id={@selected_support_script && @selected_support_script.id}
            disabled={is_nil(@selected_support_script) || @support_script_running || disconnected?(@device_connection)}
          >
            <span :if={!@support_script_running} class="lucide-play size-3.25" aria-hidden="true"></span>
            <span :if={@support_script_running} class="lucide-loader-circle size-3.5 animate-spin" aria-hidden="true"></span> Run script
          </.button>
        </div>

        <div :if={@recently_run_support_script && @recently_run_support_script_output} class="flex flex-col gap-2">
          <div class="flex items-center justify-between">
            <span class="text-xs text-content-muted">Output for "{@recently_run_support_script.name}"</span>
            <button
              class="cursor-pointer text-xs font-medium text-content-muted hover:text-content-strong"
              type="button"
              aria-label="Clear script output"
              phx-click="clear-script-output"
            >
              Clear
            </button>
          </div>
          <div class="rounded border border-line-default p-2" style="background-color: rgb(14, 16, 25);">
            <div id="support-script-term" phx-update="ignore" phx-hook="SupportScriptOutput" class="min-h-44 overflow-x-scroll"></div>
            <div id="support-script-output" class="hidden" phx-no-format>{@recently_run_support_script_output}</div>
          </div>
        </div>
      </div>
    </.card>
    """
  end

  attr(:current_scope, Scope, required: true)
  attr(:device, Device, required: true)
  attr(:addable_tags, :list, required: true)
  attr(:metadata_entries, :list, required: true)
  attr(:extension_overrides, :list, required: true)
  attr(:time_zone, :string, default: "UTC")

  defp general_info(assigns) do
    ~H"""
    <.card id="general-info-card">
      <.card_header title="General info" />
      <div class="flex flex-col px-4 pb-1.5">
        <.info_row :if={not is_nil(@device.description) && @device.description != ""} label="Description">
          <span class="text-content-body">{@device.description}</span>
        </.info_row>

        <.info_row :if={@device.latest_connection && @device.latest_connection.status == :disconnected} label="Last seen">
          <time
            id="connection-established-at"
            phx-hook="UpdatingTimeAgo"
            class="font-medium text-content-strong"
            datetime={String.replace(DateTime.to_string(DateTime.truncate(@device.latest_connection.disconnected_at, :second)), " ", "T")}
          >
            {RelativeTime.from_now(@device.latest_connection.disconnected_at)}
          </time>
          <span class="text-content-faint">{Calendar.strftime(@device.latest_connection.disconnected_at, "%b %-d, %H:%M")}</span>
        </.info_row>

        <.info_row :if={@device.latest_connection && @device.latest_connection.status != :disconnected} label="Connected">
          <time
            id="connection-established-at"
            phx-hook="UpdatingTimeAgo"
            class="font-medium text-content-strong"
            datetime={String.replace(DateTime.to_string(DateTime.truncate(@device.latest_connection.established_at, :second)), " ", "T")}
          >
            {RelativeTime.from_now(@device.latest_connection.established_at)}
          </time>
          <span class="text-content-faint">{Calendar.strftime(@device.latest_connection.established_at, "%b %-d, %H:%M")}</span>
        </.info_row>

        <.info_row :if={@device.latest_connection && @device.latest_connection.ip_address} label="IP address" class="group/ip">
          <span class="font-mono text-xs text-content-strong">{@device.latest_connection.ip_address}</span>
          <button
            id="copy-ip-address"
            type="button"
            phx-hook="CopyToClipboard"
            data-copy-value={@device.latest_connection.ip_address}
            aria-label="Copy IP address"
            title="Copy value"
            class="-ml-0.5 inline-flex shrink-0 cursor-pointer items-center text-content-faint hover:text-content-strong"
          >
            <span data-icon="copy" class="lucide-copy size-3.5"></span>
            <span data-icon="check" class="lucide-check hidden size-3.5 text-success"></span>
          </button>
        </.info_row>

        <.info_row :if={@device.firmware_metadata} label="Platform">
          <span class="font-mono text-xs text-content-muted">{@device.firmware_metadata.platform} · {@device.firmware_metadata.architecture}</span>
        </.info_row>

        <.info_row label="Added">
          <span class="font-medium text-content-strong">{Calendar.strftime(@device.inserted_at, "%b %-d, %Y")}</span>
        </.info_row>

        <.info_row label="Tags" class="min-h-11">
          <span :if={(is_nil(@device.tags) || Enum.empty?(@device.tags)) && !authorized?(:"device:update", @current_scope)} class="text-content-faint">No tags</span>
          <span :for={tag <- @device.tags || []} class="flex h-6 items-center gap-1 rounded border border-line-default bg-surface-muted px-2 text-xs font-medium whitespace-nowrap text-content-body">
            {tag}
            <button
              :if={authorized?(:"device:update", @current_scope)}
              type="button"
              phx-click="remove-tag"
              phx-value-tag={tag}
              aria-label={"Remove tag #{tag}"}
              class="-mr-0.5 cursor-pointer text-content-faint hover:text-alert-content"
            >
              <span class="lucide-x--bold size-3" aria-hidden="true"></span>
            </button>
          </span>
          <%= if authorized?(:"device:update", @current_scope) do %>
            <button
              id="add-tag-open"
              type="button"
              aria-label="Add tag"
              class="flex h-6 cursor-pointer items-center gap-1 rounded border border-dashed border-line-control pr-2 pl-1.5 text-xs font-medium text-content-muted hover:text-content-strong"
              phx-click={
                JS.remove_class("hidden", to: "#add-tag-form")
                |> JS.add_class("inline-flex", to: "#add-tag-form")
                |> JS.show(to: "#add-tag-close")
                |> JS.hide(to: "#add-tag-open")
              }
            >
              <span class="lucide-plus--bold size-3" aria-hidden="true" />Add
            </button>
            <button
              id="add-tag-close"
              type="button"
              aria-label="Cancel adding tag"
              style="display: none"
              class="flex size-6 cursor-pointer items-center justify-center rounded border border-line-default text-content-faint hover:text-alert-content"
              phx-click={
                JS.remove_class("inline-flex", to: "#add-tag-form")
                |> JS.add_class("hidden", to: "#add-tag-form")
                |> JS.hide(to: "#add-tag-close")
                |> JS.show(to: "#add-tag-open")
              }
            >
              <span class="lucide-x--bold size-3" />
            </button>
            <form
              id="add-tag-form"
              phx-submit={
                JS.push("add-tag")
                |> JS.remove_class("inline-flex", to: "#add-tag-form")
                |> JS.add_class("hidden", to: "#add-tag-form")
                |> JS.hide(to: "#add-tag-close")
                |> JS.show(to: "#add-tag-open")
              }
              class="hidden items-center gap-1"
            >
              <label for="add_tag_input" class="sr-only">Add tag</label>
              <div
                id="add-tag-autocomplete"
                class="relative"
                phx-hook="TagAutocomplete"
                data-single
                data-available-tags={Jason.encode!(@addable_tags)}
              >
                <input
                  type="text"
                  id="add_tag_input"
                  name="tag"
                  placeholder="Add tag…"
                  autocomplete="off"
                  data-tag-input
                  class="h-6 w-28 rounded border border-line-control border-b-line-strong bg-surface-raised px-2 text-xs text-content-body focus:outline focus:-outline-offset-1 focus:outline-focus-ring"
                  phx-debounce="300"
                />
                <ul
                  id="add_tag_input-suggestions"
                  phx-update="ignore"
                  data-tag-suggestions
                  role="listbox"
                  hidden
                  class="absolute z-10 mt-1 max-h-56 w-40 overflow-y-auto rounded-md border border-line-default bg-surface-overlay py-1 shadow-overlay"
                >
                </ul>
              </div>
              <.button size="sm" type="submit" aria-label="Add tag">
                Add
              </.button>
            </form>
          <% end %>
        </.info_row>

        <.info_row :if={@extension_overrides != []} label="Disabled extensions">
          <span :for={extension <- @extension_overrides} class="flex h-6 items-center rounded border border-line-default bg-surface-muted px-2 text-xs font-medium text-alert-content">
            {Extensions.display_name(extension)}
          </span>
        </.info_row>

        <div :if={@metadata_entries != []} class="flex h-9 items-center border-t border-line-subtle pt-2">
          <span class="text-label text-content-faint uppercase">Metadata</span>
        </div>
        <div :for={{key, value} <- @metadata_entries} class="group/meta flex min-h-8 items-center gap-3">
          <span class="w-26 shrink-0 text-ui/4 text-content-muted sm:w-37">{metadata_label(key)}</span>
          <div class="flex min-w-0 flex-1 items-center gap-1.5">
            <.tooltip id={"metadata-#{key}"} placement="top" class="flex min-w-0" content_class="max-w-md" enabled={long_value?(value)}>
              <span class="min-w-0 truncate font-mono text-xs/4 text-content-strong">{value}</span>
              <:content>
                <span class="font-mono text-xs break-all">{value}</span>
              </:content>
            </.tooltip>
            <button
              id={"copy-metadata-#{key}"}
              type="button"
              phx-hook="CopyToClipboard"
              data-copy-value={value}
              aria-label={"Copy #{key} value"}
              title="Copy value"
              class="shrink-0 cursor-pointer text-content-faint opacity-0 transition-opacity group-hover/meta:opacity-100 hover:text-content-strong focus-visible:opacity-100"
            >
              <span data-icon="copy" class="lucide-copy size-3.5"></span>
              <span data-icon="check" class="lucide-check hidden size-3.5 text-success"></span>
            </button>
          </div>
        </div>
      </div>
    </.card>
    """
  end

  # Metadata keys arrive as snake_case from the device, so `device_api_version`
  # reads as "Device API version".
  defp metadata_label(key) do
    key
    |> String.split("_")
    |> Enum.map_join(" ", fn
      word when word in ~w(api ip id url uuid) -> String.upcase(word)
      word -> word
    end)
    |> then(fn label -> String.upcase(String.first(label)) <> String.slice(label, 1..-1//1) end)
  end

  defp health_docs(), do: "https://github.com/nerves-hub/nerves_hub_link?tab=readme-ov-file#configure-health"

  # The gauge an engaged metric belongs to, and how it engaged. A composite
  # gauge takes the first of its keys that engaged, alert level first.
  defp engaged_for(tile, engaged) do
    Enum.find_value(engaged, fn {level, key, reason} ->
      if tile_for(key) == tile, do: {level, reason}
    end)
  end

  # Engaged metrics no featured gauge shows, so they get a gauge of their own.
  defp uncovered_reasons(latest_health, featured_keys) do
    tiles = featured_tiles(featured_keys)

    Enum.reject(StatusBadge.engaged_reasons(latest_health), fn {_level, key, _reason} -> tile_for(key) in tiles end)
  end

  defp tile_for(key) when key in ["cpu_usage_percent", "cpu_temp"], do: :cpu
  defp tile_for(key) when key in ["mem_used_percent", "mem_used_mb", "mem_size_mb"], do: :memory
  defp tile_for(key) when key in ["disk_used_percentage", "disk_total_kb", "disk_available_kb"], do: :disk
  defp tile_for("load_" <> _rest), do: :load
  defp tile_for(key), do: {:metric, key}

  # One reading in the Health card: a label, the value with its unit, and for
  # a percentage a bar under it. An engaged metric turns its value and bar the
  # level's colour and says why underneath.
  attr(:tile, :any, required: true)
  attr(:latest_metrics, :map, required: true)
  attr(:custom_labels, :map, required: true)
  attr(:engaged, :any, default: nil)

  defp gauge(%{tile: :load} = assigns) do
    ~H"""
    <div class="flex min-w-0 flex-col gap-1.5">
      <span class="text-xs font-medium text-content-muted">Load average</span>
      <div class="flex h-7.5 items-baseline gap-3">
        <span class={["w-12.5 shrink-0 text-2xl/7.5 font-medium tracking-[-0.02em]", level_text(@engaged, "text-content-strong")]}>
          {load_value(@latest_metrics["load_1min"])}
        </span>
        <span class="w-9.5 shrink-0 text-base font-medium text-content-body">{load_value(@latest_metrics["load_5min"])}</span>
        <span class="w-9.5 shrink-0 text-base font-medium text-content-body">{load_value(@latest_metrics["load_15min"])}</span>
      </div>
      <div class="flex h-4 items-center gap-3 text-xs text-content-faint">
        <span class="w-12.5 shrink-0">1 min</span><span class="w-9.5 shrink-0">5 min</span><span class="w-9.5 shrink-0">15 min</span>
      </div>
      <.engaged_reason engaged={@engaged} />
    </div>
    """
  end

  defp gauge(assigns) do
    assigns = assign(assigns, :reading, reading(assigns.tile, assigns.latest_metrics, assigns.custom_labels))

    ~H"""
    <div class="flex min-w-0 flex-col gap-1.5">
      <span class="truncate text-xs font-medium text-content-muted">
        {@reading.label}<span :if={@reading.size} class="font-normal"> · {@reading.size}</span>
      </span>
      <div :if={@reading.value} class="flex h-7.5 items-baseline gap-1">
        <span class={["text-2xl/7.5 font-medium tracking-[-0.02em]", level_text(@engaged, "text-content-strong")]}>{@reading.value}</span>
        <span :if={@reading.unit} class="text-sm text-content-muted">{@reading.unit}</span>
      </div>
      <span :if={!@reading.value} class="h-7.5 text-2xl/7.5 font-medium tracking-[-0.02em] text-content-faint">—</span>
      <div :if={@reading.percent || @reading.aside} class="flex h-4 items-center gap-2.5">
        <div :if={@reading.percent} class="flex h-1 grow rounded-full bg-line-default">
          <div class={["h-1 rounded-full", level_bar(@engaged)]} style={"width: #{min(max(@reading.percent, 0), 100)}%"}></div>
        </div>
        <span :if={@reading.aside} class="flex shrink-0 items-center gap-0.75 text-xs text-content-muted">
          <span :if={@reading.aside_icon} class={[@reading.aside_icon, "size-3.25 text-content-faint"]} aria-hidden="true"></span>
          {@reading.aside}
        </span>
      </div>
      <.engaged_reason engaged={@engaged} />
    </div>
    """
  end

  attr(:engaged, :any)

  defp engaged_reason(assigns) do
    ~H"""
    <span :if={@engaged} class={["text-xs font-medium", level_text(@engaged, nil)]}>{engaged_detail(elem(@engaged, 1))}</span>
    """
  end

  defp level_text({"unhealthy", _reason}, _default), do: "text-alert-content"
  defp level_text({"warning", _reason}, _default), do: "text-warning-content"
  defp level_text(_not_engaged, default), do: default

  defp level_bar({"unhealthy", _reason}), do: "bg-alert"
  defp level_bar({"warning", _reason}), do: "bg-warning"
  defp level_bar(_not_engaged), do: "bg-content-faint"

  defp load_value(value) when is_number(value), do: Utils.format_number(Float.round(value / 1, 2))
  defp load_value(_not_reported), do: "—"

  # A gauge's reading: the label and the total it's out of, the value with its
  # unit, a bar for a share, and beside the bar what the value doesn't say.
  defp reading(:cpu, metrics, _labels) do
    temperature = metrics["cpu_temp"]

    %{
      label: "CPU",
      size: nil,
      value: is_number(metrics["cpu_usage_percent"]) && round(metrics["cpu_usage_percent"]),
      unit: "%",
      percent: number_or_nil(metrics["cpu_usage_percent"]),
      aside: is_number(temperature) && "#{round(temperature)} °C",
      aside_icon: "lucide-thermometer"
    }
  end

  defp reading(:memory, metrics, _labels) do
    used = metrics["mem_used_mb"]
    percent = number_or_nil(metrics["mem_used_percent"])

    %{
      label: "Memory",
      size: is_number(metrics["mem_size_mb"]) && "#{gigabytes(metrics["mem_size_mb"] / 1024)} GB",
      value: if(is_number(used), do: number_to_delimited(used, precision: 0), else: percent && round(percent)),
      unit: if(is_number(used), do: "MB", else: percent && "%"),
      percent: percent,
      aside: is_number(used) && percent && "#{round(percent)}%",
      aside_icon: nil
    }
  end

  defp reading(:disk, metrics, _labels) do
    %{"disk_total_kb" => total, "disk_available_kb" => available} =
      Map.merge(%{"disk_total_kb" => nil, "disk_available_kb" => nil}, metrics)

    percent = number_or_nil(metrics["disk_used_percentage"])
    sizes? = is_number(total) and is_number(available)

    %{
      label: "Disk",
      size: is_number(total) && "#{gigabytes(total / 1_048_576)} GB",
      value: if(sizes?, do: gigabytes((total - available) / 1_048_576), else: percent && round(percent)),
      unit: if(sizes?, do: "GB", else: percent && "%"),
      percent: percent,
      aside: sizes? && percent && "#{round(percent)}%",
      aside_icon: nil
    }
  end

  defp reading({:metric, key}, metrics, labels) do
    value = metrics[key]

    %{
      label: MetricLabels.label(key, labels),
      size: nil,
      value: is_number(value) && Utils.nice_round(value),
      unit: nil,
      percent: nil,
      aside: nil,
      aside_icon: nil
    }
  end

  defp number_or_nil(value) when is_number(value), do: value
  defp number_or_nil(_not_a_number), do: nil

  defp gigabytes(value), do: Utils.format_number(Float.round(value / 1, 1))

  # The dropdown is built from firmware that still exists, so a request naming
  # firmware the lookup cannot find comes from a page left open while someone
  # else deleted it. Nothing to send a device to.
  defp unavailable_firmware_error(socket) do
    socket
    |> put_flash(:error, "That firmware is no longer available and cannot be sent to a device.")
    |> halt()
  end

  defp already_updating_error(socket) do
    socket
    |> put_flash(:error, "The device is already updating. Wait for that update to finish before sending another.")
    |> halt()
  end

  defp engaged_detail(%{"aggregation" => "count"} = reason) do
    "threshold #{Utils.format_number(reason["threshold"])} in #{Utils.format_period(reason["period_seconds"])}"
  end

  defp engaged_detail(%{"aggregation" => "share"} = reason) do
    direction = if reason["operator"] == "lte", do: "at or under", else: "at or over"

    "#{direction} #{Utils.format_number(reason["threshold"])} for #{reason["value"]}% of #{Utils.format_period(reason["period_seconds"])}"
  end

  defp engaged_detail(reason), do: "threshold #{Utils.format_number(reason["threshold"])}"
end
