defmodule NervesHubWeb.Live.Devices.DeviceHealth do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Devices
  alias NervesHub.Devices.Metrics
  alias NervesHub.Tracker

  alias NervesHubWeb.Components.HealthHeader
  alias NervesHubWeb.Components.HealthSection

  alias Phoenix.Socket.Broadcast

  @check_health_interval 60_000
  @time_frame_opts [
    {"hour", 1},
    {"day", 1},
    {"day", 7}
  ]
  @default_time_frame {"hour", 1}
  @default_chart_type :scatter

  def mount(%{"device_identifier" => device_identifier}, _session, socket) do
    %{org: org} = socket.assigns

    device = Devices.get_device_by_identifier!(org, device_identifier)

    if connected?(socket) do
      socket.endpoint.subscribe("device:#{device.identifier}:internal")
    end

    socket
    |> page_title("Device #{device.identifier} - Health")
    |> assign(:device, device)
    |> assign(:status, Tracker.status(device))
    |> assign(:time_frame, @default_time_frame)
    |> assign(:time_frame_opts, @time_frame_opts)
    |> assign(:chart_type, @default_chart_type)
    |> assign(:latest_metrics, Metrics.get_latest_metric_set_for_device(device.id))
    |> schedule_health_check_timer()
    |> assign_charts()
    |> ok()
  end

  def handle_event("set-time-frame", %{"unit" => unit, "amount" => amount}, socket) do
    payload = %{unit: get_time_unit({unit, String.to_integer(amount)})}

    socket
    |> assign(:time_frame, {unit, String.to_integer(amount)})
    |> push_event("update-time-unit", payload)
    |> update_charts()
    |> noreply()
  end

  def handle_event("scatter-chart", _, socket) do
    socket
    |> assign(:chart_type, :scatter)
    |> noreply()
  end

  def handle_event("line-chart", _, socket) do
    socket
    |> assign(:chart_type, :line)
    |> noreply()
  end

  def handle_event("toggle-health-check-auto-refresh", _value, socket) do
    if timer_ref = socket.assigns.health_check_timer do
      _ = Process.cancel_timer(timer_ref)
      {:noreply, assign(socket, :health_check_timer, nil)}
    else
      {:noreply, schedule_health_check_timer(socket)}
    end
  end

  def handle_info(:check_health_interval, socket) do
    timer_ref = Process.send_after(self(), :check_health_interval, @check_health_interval)

    socket.endpoint.broadcast("device:#{socket.assigns.device.id}", "check_health", %{})

    socket
    |> assign(:health_check_timer, timer_ref)
    |> noreply()
  end

  def handle_info(
        %Broadcast{event: "health_check_report"},
        %{assigns: %{device: device}} = socket
      ) do
    socket
    |> assign(:latest_metrics, Metrics.get_latest_metric_set_for_device(device.id))
    |> update_charts()
    |> noreply()
  end

  # Ignore other events for now
  def handle_info(_event, socket), do: {:noreply, socket}

  def assign_charts(
        %{
          assigns: %{
            device: device,
            time_frame: time_frame
          }
        } =
          socket
      ) do
    charts =
      create_chart_data(device.id, time_frame)

    socket |> assign(:charts, charts)
  end

  def update_charts(
        %{
          assigns: %{
            device: device,
            time_frame: time_frame
          }
        } =
          socket
      ) do
    device.id
    |> create_chart_data(time_frame)
    |> Enum.reduce(socket, fn %{type: type, data: data}, socket ->
      type = if is_binary(type), do: type, else: Atom.to_string(type)
      push_event(socket, "update-charts", %{type: type, data: data})
    end)
  end

  def create_chart_data(device_id, time_frame) do
    default = create_default_chart_data(device_id, time_frame)
    custom = create_custom_chart_data(device_id, time_frame)

    # Concat default and custom metrics and keep only non-nil results
    Enum.concat(default, custom)
    |> Enum.filter(& &1)
  end

  def create_default_chart_data(device_id, time_frame) do
    Metrics.default_metric_types()
    |> Enum.map(fn type ->
      data =
        device_id
        |> Metrics.get_device_metrics_by_key(Atom.to_string(type), time_frame)
        |> organize_metrics_for_chart()

      unless data == [] do
        %{
          type: Atom.to_string(type),
          data: data,
          max: get_max_value(type, data),
          unit: get_time_unit(time_frame)
        }
      end
    end)
  end

  def create_custom_chart_data(device_id, time_frame) do
    device_id
    |> Metrics.get_custom_metrics_for_device(time_frame)
    |> Enum.group_by(& &1.key)
    |> Enum.map(fn {type, metrics} ->
      dbg(type)

      %{
        type: type,
        data: organize_metrics_for_chart(metrics),
        max: get_max_value(:custom, metrics),
        unit: get_time_unit(time_frame)
      }
    end)
  end

  defp organize_metrics_for_chart(metrics) do
    metrics
    |> Enum.map(fn %{inserted_at: timestamp, value: value} ->
      %{x: DateTime.to_string(timestamp), y: value}
    end)
  end

  defp get_time_unit({"hour", _}), do: "minute"
  defp get_time_unit({"day", 1}), do: "hour"
  defp get_time_unit({"day", _}), do: "day"

  defp get_max_value(type, data, memory_size \\ 0)
  defp get_max_value(_type, data, _memory_size) when data == [], do: 0
  defp get_max_value(:load_1min, data, _memory_size), do: get_cpu_load_max_value(data)
  defp get_max_value(:load_5min, data, _memory_size), do: get_cpu_load_max_value(data)
  defp get_max_value(:load_15min, data, _memory_size), do: get_cpu_load_max_value(data)
  defp get_max_value(:custom, data, _memory_size), do: get_custom_max_value(data)
  defp get_max_value(_, _, _memory_size), do: 100
  # TODO: Max value for memory size
  # TODO: Make prettier message when metrics are missing
  # TODO: Clean up - also app.js

  defp get_cpu_load_max_value(data) do
    data
    |> Enum.max_by(& &1.y)
    |> Map.get(:y)
    |> ceil()
    |> max(1)
  end

  defp get_custom_max_value(data) do
    data
    |> Enum.max_by(& &1.y)
    |> Map.get(:y)
  end

  defp schedule_health_check_timer(socket) do
    if connected?(socket) and device_health_check_enabled?() do
      timer_ref = Process.send_after(self(), :check_health_interval, 500)
      assign(socket, :health_check_timer, timer_ref)
    else
      assign(socket, :health_check_timer, nil)
    end
  end

  defp device_health_check_enabled?() do
    Application.get_env(:nerves_hub, :device_health_check_enabled)
  end
end
