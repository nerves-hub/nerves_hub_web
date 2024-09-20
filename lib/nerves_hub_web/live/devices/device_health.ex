defmodule NervesHubWeb.Live.Devices.DeviceHealth do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Devices
  alias NervesHub.Devices.Metrics
  alias NervesHub.Tracker

  alias NervesHubWeb.Components.HealthHeader

  alias Phoenix.Socket.Broadcast

  @check_health_interval 60_000
  @time_frame_opts [
    {"hour", 1},
    {"day", 1},
    {"day", 7}
  ]
  @default_time_frame {"hour", 1}

  # Metric types with belonging titles to display as default.
  # Also sets order of charts.
  @default_metric_types [
    used_mb: "Memory Usage (MB)",
    load_1min: "Load Average 1 Min",
    load_5min: "Load Average 5 Min",
    load_15min: "Load Average 15 Min",
    cpu_temp: "CPU Temperature (Celsius)"
  ]

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
            time_frame: time_frame,
            latest_metrics: latest_metrics
          }
        } =
          socket
      ) do
    memory_size = latest_metrics[:size_mb]

    charts =
      create_chart_data(device.id, time_frame, memory_size)

    socket |> assign(:charts, charts)
  end

  @doc """
  There are three cases for chart updates:
    - Create hooks if data previously was empty.
    - Update existing hooks with new data via push_event.
    - Clear hooks if there's no data for selected time frame.
  """
  def update_charts(%{assigns: %{charts: charts}} = socket) when charts == [],
    do: assign_charts(socket)

  def update_charts(
        %{
          assigns: %{
            device: device,
            time_frame: time_frame,
            latest_metrics: latest_metrics
          }
        } =
          socket
      ) do
    data = create_chart_data(device.id, time_frame, latest_metrics[:size_mb])

    if data == [] do
      socket |> assign(:charts, [])
    else
      Enum.each(data, fn %{type: type, data: data} ->
        type = if is_binary(type), do: type, else: Atom.to_string(type)
        push_event(socket, "update-charts", %{type: type, data: data})
      end)
    end
  end

  def create_chart_data(device_id, time_frame, memory_size) do
    default = create_default_chart_data(device_id, time_frame, memory_size)
    custom = create_custom_chart_data(device_id, time_frame)

    # Concat default and custom metrics and keep only non-nil results
    Enum.concat(default, custom)
    |> Enum.filter(& &1)
  end

  def create_default_chart_data(device_id, {unit, _} = time_frame, memory_size) do
    @default_metric_types
    |> Enum.map(fn {type, title} ->
      data =
        device_id
        |> Metrics.get_device_metrics_by_key(Atom.to_string(type), time_frame)
        |> get_max_per_hour(unit)
        |> organize_metrics_for_chart()

      unless data == [] do
        %{
          type: Atom.to_string(type),
          title: title,
          data: data,
          max: get_max_value(type, data, memory_size),
          unit: get_time_unit(time_frame)
        }
      end
    end)
  end

  def create_custom_chart_data(device_id, {unit, _} = time_frame) do
    device_id
    |> Metrics.get_custom_metrics_for_device(time_frame)
    |> Enum.group_by(& &1.key)
    |> Enum.map(fn {type, metrics} ->
      data =
        metrics
        |> get_max_per_hour(unit)
        |> organize_metrics_for_chart()

      title = String.replace(type, "_", " ") |> String.capitalize()

      %{
        type: type,
        title: title,
        data: data,
        max: get_max_value(:custom, data),
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

  # Do nothing if time frame unit is hour
  defp get_max_per_hour(metrics, "hour"), do: metrics

  defp get_max_per_hour(metrics, _unit) do
    metrics
    |> Enum.group_by(& &1.inserted_at.hour)
    |> Enum.map(fn {_key, val} ->
      Enum.max_by(val, & &1.value)
    end)
    |> Enum.sort_by(& &1.inserted_at)
  end

  defp get_time_unit({"hour", _}), do: "minute"
  defp get_time_unit({"day", 1}), do: "hour"
  defp get_time_unit({"day", _}), do: "day"

  defp get_max_value(_type, data, _memory_size) when data == [], do: 0

  defp get_max_value(type, data, memory_size) do
    case type do
      :load_1min -> get_cpu_load_max_value(data)
      :load_5min -> get_cpu_load_max_value(data)
      :load_15min -> get_cpu_load_max_value(data)
      :used_mb -> memory_size
      _ -> 100
    end
  end

  defp get_max_value(:custom, data) do
    data
    |> Enum.max_by(& &1.y)
    |> Map.get(:y)
  end

  defp get_cpu_load_max_value(data) do
    data
    |> Enum.max_by(& &1.y)
    |> Map.get(:y)
    |> ceil()
    |> max(1)
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
