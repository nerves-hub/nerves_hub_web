defmodule NervesHubWeb.Live.Devices.DeviceHealth do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Devices
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

  @metrics_structure %{
    cpu_temp: [],
    load_15min: [],
    load_1min: [],
    load_5min: [],
    size_mb: [],
    used_mb: [],
    used_percent: []
  }

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
    |> schedule_health_check_timer()
    |> assign_metrics()
    |> ok()
  end

  def handle_event("set-time-frame", %{"unit" => unit, "amount" => amount}, socket) do
    socket
    |> assign(:time_frame, {unit, String.to_integer(amount)})
    |> assign_metrics()
    |> noreply()
  end

  def handle_event("scatter-chart", _, socket) do
    socket
    |> assign(:chart_type, :scatter)
    |> assign_metrics()
    |> noreply()
  end

  def handle_event("line-chart", _, socket) do
    socket
    |> assign(:chart_type, :line)
    |> assign_metrics()
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

  def handle_info(%Broadcast{event: "health_check_report"}, socket) do
    socket
    |> assign_metrics()
    |> noreply()
  end

  # Ignore other events for now
  def handle_info(_event, socket), do: {:noreply, socket}

  @doc """
  Organizes health data into metrics structure suitable for Contex plots.
  """
  def organize_data(health) do
    Enum.reduce(health, @metrics_structure, fn h, acc ->
      metrics = h.data["metrics"]

      if metrics do
        ts = NaiveDateTime.from_iso8601!(h.data["timestamp"])

        acc
        |> Map.keys()
        |> Enum.reduce(acc, fn key, acc ->
          str_key = to_string(key)
          Map.put(acc, key, [[ts, metrics[str_key]] | acc[key]])
        end)
      else
        acc
      end
    end)
  end

  defp assign_metrics(
         %{
           assigns: %{
             device: device,
             chart_type: chart_type,
             time_frame: {unit, amount} = time_frame
           }
         } = socket
       ) do
    latest_health = Devices.get_latest_health(device.id)

    {memory_size, memory_usage} =
      case latest_health do
        %{data: %{"metrics" => metrics}} -> {metrics["size_mb"], metrics["used_percent"]}
        _ -> {0, 0}
      end

    metrics =
      device.id
      |> Devices.get_device_health(unit, amount)
      |> organize_data()

    socket
    |> assign(:latest_health, latest_health)
    |> assign(:memory_size, memory_size)
    |> assign(:memory_usage, memory_usage)
    |> assign(:graphs, create_graphs(metrics, chart_type, memory_size, time_frame))
  end

  defp create_graphs(metrics, chart_type, memory_size, time_frame) do
    metrics
    |> Enum.reduce(%{}, fn {metric_type, data}, acc ->
      case metric_type do
        :size_mb ->
          acc

        _ ->
          max_value = get_max_value(metric_type, data, memory_size)
          chart_svg = create_chart(data, chart_type, max_value, time_frame)

          Map.put(acc, metric_type, chart_svg)
      end
    end)
  end

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

  defp get_cpu_load_max_value(data) do
    data
    |> Enum.max_by(fn [_, value] -> value end)
    |> List.last()
    |> ceil()
    |> max(1)
  end

  defp create_chart(data, _chart_type, _max_value, _time_unit)
       when data == [],
       do: raw("<p class=\"metrics-text\">No data for selected period</p>")

  defp create_chart(data, chart_type, max_value, time_unit) do
    now = NaiveDateTime.utc_now()

    x_scale =
      Contex.TimeScale.new()
      |> Contex.TimeScale.domain(time_scale_start(now, time_unit), now)
      |> Contex.TimeScale.interval_count(20)

    y_scale =
      Contex.ContinuousLinearScale.new()
      |> Contex.ContinuousLinearScale.domain(0, max_value)

    chart =
      case chart_type do
        :line -> Contex.LinePlot
        :scatter -> Contex.PointPlot
      end

    options = [
      smoothed: false,
      colour_palette: ["f8d98b"],
      custom_x_scale: x_scale,
      custom_y_scale: y_scale
    ]

    data
    |> Contex.Dataset.new()
    |> Contex.Plot.new(chart, 800, 300, options)
    |> Map.put(:margins, %{left: 60, right: 40, top: 20, bottom: 70})
    |> Contex.Plot.to_svg()
  end

  defp time_scale_start(now, {"hour", amount}), do: NaiveDateTime.shift(now, hour: -amount)
  defp time_scale_start(now, {"day", amount}), do: NaiveDateTime.shift(now, day: -amount)

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
