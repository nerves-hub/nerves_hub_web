defmodule NervesHubWeb.Components.DevicePage.NetworksTab do
  @moduledoc """
  The networks a device fronts, as reported through the `components`
  extension: a Z-Wave controller's paired devices, a BLE hub's sensors —
  groupings of peers that talk *to* the device rather than being part of it.

  Renders the same component boxes as the Details tab's assemblies (see
  `NervesHubWeb.Components.DeviceComponents`); the split between the tabs is
  the topology's own: assemblies are what the device is, networks are what it
  reaches.
  """

  use NervesHubWeb, tab_component: :networks

  alias NervesHub.Devices.Components
  alias NervesHub.Devices.Health
  alias NervesHub.Devices.Metrics
  alias NervesHubWeb.Components.DeviceComponents
  alias NervesHubWeb.Components.DevicePage.SharedComponentsHandlers
  alias Phoenix.Socket.Broadcast

  def tab_params(_params, _uri, %{assigns: %{device: device, product: product}} = socket) do
    topology =
      case device.component_topology do
        %{topology: topology} -> topology
        _ -> nil
      end

    socket
    |> assign(:network_topology, topology)
    |> assign(:network_metadata, SharedComponentsHandlers.health_metadata(device))
    |> assign(:network_latest_metrics, Metrics.get_latest_metric_set(device.id))
    |> assign(
      :can_manage_network_components,
      SharedComponentsHandlers.can_manage_components?(socket.assigns.current_scope, product, device)
    )
    |> cont()
  end

  def cleanup() do
    [
      :network_topology,
      :network_metadata,
      :network_latest_metrics,
      :can_manage_network_components
    ]
  end

  def hooked_async(_name, _result, socket), do: {:cont, socket}

  def hooked_event("components-run-action", params, socket) do
    socket
    |> SharedComponentsHandlers.run_action(params)
    |> halt()
  end

  def hooked_event("components-set-mode", params, socket) do
    socket
    |> SharedComponentsHandlers.set_mode(params)
    |> halt()
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  def hooked_info(%Broadcast{event: "components:updated"}, %{assigns: %{device: device}} = socket) do
    topology =
      case Components.get_topology(device.id) do
        %{topology: topology} -> topology
        _ -> nil
      end

    socket
    |> assign(:network_topology, topology)
    |> halt()
  end

  def hooked_info(%Broadcast{event: event, payload: payload}, socket)
      when event in ["components:action_result", "components:mode_result"] do
    socket
    |> SharedComponentsHandlers.flash_result(payload)
    |> halt()
  end

  def hooked_info(%Broadcast{event: "metrics_report"}, %{assigns: %{device: device}} = socket) do
    socket
    |> assign(:network_latest_metrics, Metrics.get_latest_metric_set(device.id))
    |> halt()
  end

  def hooked_info(%Broadcast{event: "health_check_report"}, %{assigns: %{device: device}} = socket) do
    device = %{device | latest_health: Health.get_latest_health(device.id)}

    socket
    |> assign(:device, device)
    |> assign(:network_latest_metrics, Metrics.get_latest_metric_set(device.id))
    |> assign(:network_metadata, SharedComponentsHandlers.health_metadata(device))
    |> halt()
  end

  def hooked_info(_event, socket), do: {:cont, socket}

  def render(assigns) do
    # `assign/3` rather than `Map.put/3`, so LiveView's change tracking sees
    # the value move when an extension toggle changes mid-session.
    assigns =
      assign(
        assigns,
        :components_enabled?,
        SharedComponentsHandlers.components_enabled?(assigns.product, assigns.device)
      )

    ~H"""
    <div
      id="networks-tab"
      phx-mounted={JS.remove_class("opacity-0")}
      class="phx-click-loading:opacity-50 tab-content flex h-full flex-col gap-4 p-6 opacity-0 transition-all duration-500"
    >
      <div :if={!@components_enabled? && networks(@network_topology) == []} class="bg-surface-raised border-base-700 shadow-device-details-content flex flex-col rounded border">
        <div class="text-base-50 flex h-14 items-center pr-3 pl-4 leading-6 font-medium">Networks</div>
        <div class="text-base-500 flex items-center gap-2 px-4 pt-2 pb-4">
          Component reporting is not enabled {if(!@product.extensions.components, do: "for your product", else: "for this device")}.
        </div>
      </div>

      <div :if={@components_enabled? && networks(@network_topology) == []} class="bg-surface-raised border-base-700 shadow-device-details-content flex flex-col rounded border">
        <div class="text-base-50 flex h-14 items-center pr-3 pl-4 leading-6 font-medium">Networks</div>
        <div class="text-base-500 flex items-center gap-2 px-4 pt-2 pb-4">
          This device hasn't reported any networks.
        </div>
      </div>

      <div class="grid grid-cols-1 gap-4 xl:grid-cols-2">
        <DeviceComponents.group_box
          :for={network <- networks(@network_topology)}
          group={network}
          members_key="peers"
          latest_metrics={@network_latest_metrics}
          metadata={@network_metadata}
          can_manage={@can_manage_network_components}
        />
      </div>
    </div>
    """
  end

  defp networks(topology) do
    case topology do
      %{"networks" => networks} when is_list(networks) -> networks
      _ -> []
    end
  end
end
