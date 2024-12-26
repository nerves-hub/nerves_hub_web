defmodule NervesHubWeb.Live.Devices.DeviceHealth do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Metrics
  alias NervesHub.Extensions.Health

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
  @default_metrics [
    {"load_1min", "Load Average 1 Min"},
    {"load_5min", "Load Average 5 Min"},
    {"load_15min", "Load Average 15 Min"},
    {"mem_used_mb", "Memory Usage (MB)"},
    {"mem_used_percent", "Memory Usage (%)"},
    {"disk_used_percentage", "Disk Usage (%)"},
    {"cpu_usage_percent", "CPU Usage (%)"},
    {"cpu_temp", "CPU Temperature (Celsius)"}
  ]

  # Will not be rendered as chart.
  @no_chart_metrics [
    "mem_size_mb",
    "disk_total_kb"
  ]

  def mount(%{"device_identifier" => device_identifier}, _session, socket) do
    %{org: org} = socket.assigns

    device = Devices.get_device_by_identifier!(org, device_identifier)

    if connected?(socket) do
      socket.endpoint.subscribe("device:#{device.identifier}:internal")
      socket.endpoint.subscribe("device:#{device.identifier}:extensions")
    end

    socket
    |> page_title("Device #{device.identifier} - Health")
    |> assign(:device, device)
    |> assign(:latest_connection, Connections.get_latest_for_device(device.id))
    |> assign(:time_frame, @default_time_frame)
    |> assign(:time_frame_opts, @time_frame_opts)
    |> assign(:latest_metrics, Metrics.get_latest_metric_set(device.id))
    |> schedule_health_check_timer()
    |> ok()
  end

  def handle_params(_params, _session, socket) do
    socket
    |> assign_charts()
    |> update_charts()
    |> noreply()
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

    Health.request_health_check(socket.assigns.device)

    socket
    |> assign(:health_check_timer, timer_ref)
    |> noreply()
  end

  def handle_info(
        %Broadcast{event: "health_check_report"},
        %{assigns: %{device: device}} = socket
      ) do
    socket
    |> assign(:latest_metrics, Metrics.get_latest_metric_set(device.id))
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
    charts =
      create_chart_data(device.id, time_frame, latest_metrics["mem_size_mb"])

    socket |> assign(:charts, charts)
  end

  @doc """
  There are four cases for chart updates:
    - Create hooks if data previously was empty.
    - Clear hooks if there's no data for selected time frame.
    - Do a push_patch to render more or less charts if custom types varies for time frames.
    - Update existing hooks with new data via push_event (should happen most frequent).
  """
  def update_charts(%{assigns: %{charts: charts}} = socket) when charts == [],
    do: assign_charts(socket)

  def update_charts(
        %{
          assigns: %{
            product: product,
            org: org,
            device: device,
            time_frame: time_frame,
            latest_metrics: latest_metrics,
            charts: charts
          }
        } =
          socket
      ) do
    data = create_chart_data(device.id, time_frame, latest_metrics["size_mb"])

    cond do
      data == [] ->
        assign(socket, :charts, [])

      types(charts) != types(data) ->
        push_patch(socket,
          to: ~p"/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health"
        )

      true ->
        Enum.reduce(data, socket, fn %{type: type, data: data}, socket ->
          type = if is_binary(type), do: type, else: Atom.to_string(type)
          push_event(socket, "update-charts", %{type: type, data: data})
        end)
    end
  end

  defp types(data) do
    Enum.map(data, &Map.get(&1, :type))
  end

  def create_chart_data(device_id, {unit, _} = time_frame, memory_size) do
    device_id
    |> Metrics.get_device_metrics(time_frame)
    |> Enum.group_by(& &1.key)
    |> filter_and_sort()
    |> Enum.map(fn {type, metrics} ->
      data = organize_metrics_for_chart(metrics, unit)

      # Build structure for rendering charts
      %{
        type: type,
        title: title(type),
        data: data,
        max: get_max_value(type, data, memory_size),
        min: get_min_value(data),
        unit: get_time_unit(time_frame)
      }
    end)
  end

  defp filter_and_sort(metrics) do
    metrics
    |> Enum.reject(fn {type, _} -> type in @no_chart_metrics end)
    |> Enum.sort_by(fn {type, _} ->
      # Sorts list by @default_metrics order
      Enum.find_index(@default_metrics, fn {default_type, _} ->
        default_type == type
      end)
    end)
  end

  defp organize_metrics_for_chart(metrics, unit) do
    metrics
    |> get_max_per_hour(unit)
    |> Enum.map(fn %{inserted_at: timestamp, value: value} ->
      %{x: DateTime.to_string(timestamp), y: value}
    end)
  end

  defp title(type) do
    case Enum.find(@default_metrics, fn {default_type, _} -> default_type == type end) do
      {_, title} ->
        title

      nil ->
        type
        |> String.replace("_", " ")
        |> String.capitalize()
    end
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
      "load_" <> _ ->
        cpu_load_max_value(data)

      "mem_used_mb" ->
        memory_size

      type
      when type in ["mem_used_percent", "cpu_temp", "cpu_usage_percent", "disk_used_percentage"] ->
        100

      _ ->
        data
        |> Enum.max_by(& &1.y)
        |> Map.get(:y)
    end
  end

  defp cpu_load_max_value(data) do
    data
    |> Enum.max_by(& &1.y)
    |> Map.get(:y)
    |> ceil()
    |> max(1)
  end

  defp get_min_value(data) do
    data
    |> Enum.min_by(& &1.y)
    |> Map.get(:y)
  end

  defp schedule_health_check_timer(%{assigns: %{device: device, product: product}} = socket) do
    if connected?(socket) and product.extensions.health and device.extensions.health do
      timer_ref = Process.send_after(self(), :check_health_interval, 500)
      assign(socket, :health_check_timer, timer_ref)
    else
      assign(socket, :health_check_timer, nil)
    end
  end
end
