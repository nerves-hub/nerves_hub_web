defmodule NervesHubWeb.Components.DevicePage.SharedComponentsHandlers do
  @moduledoc """
  The component-topology behavior the Details and Networks tabs share.

  Component boxes appear on both tabs (assemblies on Details, networks of
  peers on Networks), and only the active tab's hooks are attached — so each
  tab carries its own thin `hooked_event`/`hooked_info` clauses and routes
  them here.

  Everything that leaves here for a device is authorized against the current
  scope and audited by `NervesHub.Devices.Components`. Everything that arrives
  from a device is already sanitized/bounded, and is only ever rendered as
  text.
  """

  import NervesHubWeb.Helpers.Authorization
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias NervesHub.Devices.Components
  alias NervesHubWeb.Components.DeviceComponents

  @doc """
  Assign `:component_topology` (the sanitized topology map, or `nil`) and
  `:component_metadata` (the health metadata map mode values are read from).
  """
  def assign_topology(%{assigns: %{device: device}} = socket) do
    topology =
      case device.component_topology do
        %{topology: topology} -> topology
        _ -> nil
      end

    socket
    |> assign(:component_topology, topology)
    |> assign(:component_metadata, health_metadata(device))
  end

  @doc """
  Re-read the topology after a `"components:updated"` report.
  """
  def refresh_topology(%{assigns: %{device: device}} = socket) do
    topology =
      case Components.get_topology(device.id) do
        %{topology: topology} -> topology
        _ -> nil
      end

    assign(socket, :component_topology, topology)
  end

  @doc """
  Handle the `components-run-action` click: authorize, audit, and send the
  request to the device.
  """
  def run_action(socket, %{"component" => component, "action" => action})
      when is_binary(component) and is_binary(action) do
    %{device: device, user: user} = socket.assigns

    authorized!(:"device:components:run-action", socket.assigns.current_scope)

    case Components.request_action(user, device, component, action) do
      {:ok, _ref} ->
        put_flash(socket, :info, ~s(Requested action "#{action}" on "#{component}".))

      {:error, _reason} ->
        put_flash(socket, :error, "Failed to send the action request.")
    end
  end

  def run_action(socket, _params), do: socket

  @doc """
  Handle the `components-set-mode` change: authorize, audit, and send the
  request to the device.
  """
  def set_mode(socket, %{"component" => component, "mode" => mode, "value" => value})
      when is_binary(component) and is_binary(mode) and is_binary(value) and value != "" do
    %{device: device, user: user} = socket.assigns

    authorized!(:"device:components:set-mode", socket.assigns.current_scope)

    case Components.request_mode_change(user, device, component, mode, value) do
      {:ok, _ref} ->
        put_flash(socket, :info, ~s(Requested mode "#{mode}" be set to "#{value}" on "#{component}".))

      {:error, _reason} ->
        put_flash(socket, :error, "Failed to send the mode change request.")
    end
  end

  def set_mode(socket, _params), do: socket

  @doc """
  Flash the result a device reported for an action or mode request.

  The payload is device-supplied (already bounded by the extension); it is
  interpolated into text only.
  """
  def flash_result(socket, payload) do
    subject =
      case payload do
        %{"action" => action, "component" => component} ->
          ~s(Action "#{action}" on "#{component}")

        %{"mode" => mode, "component" => component} ->
          ~s(Mode "#{mode}" on "#{component}")

        _ ->
          "A component request"
      end

    output =
      case payload["output"] do
        output when is_binary(output) and output != "" -> ": #{output}"
        _ -> "."
      end

    case payload["status"] do
      "ok" -> put_flash(socket, :info, "#{subject} completed#{output}")
      _ -> put_flash(socket, :error, "#{subject} failed#{output}")
    end
  end

  @doc """
  Whether the current scope may invoke actions and set modes.

  One capability on purpose: both are "make the device do something",
  identically audited, so splitting the buttons from the dropdowns would be a
  distinction without a difference.
  """
  def can_manage_components?(scope) do
    authorized?(:"device:components:run-action", scope)
  end

  @doc """
  The health metadata map, which mode dropdowns read their current value from.
  See `NervesHubWeb.Components.DeviceComponents.current_mode_value/2`.
  """
  def health_metadata(device) do
    case device.latest_health do
      %{data: %{"metadata" => metadata}} when is_map(metadata) -> metadata
      _ -> %{}
    end
  end

  @doc """
  Whether the topology has anything for a tab to show.
  """
  def any_groups?(topology, key) do
    is_map(topology) and is_list(topology[key]) and topology[key] != []
  end

  defdelegate title(entry), to: DeviceComponents
end
