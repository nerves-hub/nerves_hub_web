defmodule NervesHubWeb.Live.Devices.DeviceHealth do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Devices
  alias NervesHub.Tracker

  alias NervesHubWeb.Components.HealthHeader

  alias Phoenix.Socket.Broadcast

  def mount(%{"device_identifier" => device_identifier}, _session, socket) do
    %{org: org, product: _product} = socket.assigns

    device = Devices.get_device_by_identifier!(org, device_identifier)

    if connected?(socket) do
      socket.endpoint.subscribe("device:#{device.identifier}:internal")
    end

    socket
    |> page_title("Device #{device.identifier} - Health")
    |> assign(:device, device)
    |> assign(:status, Tracker.status(device))
    # TODO: Make sure health reports are coming in correctly from channel
    # |> schedule_health_check_timer()
    |> assign_metrics()
    |> ok()
  end

  def handle_info(:check_health_interval, socket) do
    timer_ref = Process.send_after(self(), :check_health_interval, 2_000)

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

  def assign_metrics(%{assigns: %{device: device}} = socket) do
    metrics = Devices.get_device_metrics(device.id)

    # TODO: Handle empty metrics

    socket
    |> assign(:cpu_temp_line_plot, create_line_plot_svg(device.id, "cpu_temp"))
    |> assign(:load_1min_line_plot, create_line_plot_svg(device.id, "load_1min"))
    |> assign(:load_5min_line_plot, create_line_plot_svg(device.id, "load_5min"))
    |> assign(:load_15min_line_plot, create_line_plot_svg(device.id, "load_15min"))
    |> assign(:used_mb_line_plot, create_line_plot_svg(device.id, "used_mb"))
    |> assign(:used_percent_line_plot, create_line_plot_svg(device.id, "used_percent"))
  end

  defp create_line_plot_svg(device_id, metric_type) do
    # TODO: consider getting all metrics at once
    data = Devices.get_single_metric(device_id, metric_type)

    x_scale =
      Contex.TimeScale.new()
      |> Contex.TimeScale.domain(Enum.map(data, &hd/1))
      |> Contex.TimeScale.interval_count(35)

    options = [
      smoothed: false,
      colour_palette: ["ffffff"],
      custom_x_scale: x_scale
    ]

    data
    |> Contex.Dataset.new()
    |> Contex.Plot.new(Contex.LinePlot, 600, 400, options)
    |> Contex.Plot.to_svg()
  end

  # TODO: Probably remove this
  defp create_sparkline_svg(metrics) when is_list(metrics) do
    metrics
    |> Contex.Sparkline.new()
    |> Map.put(:width, 500)
    |> Map.put(:height, 200)
    |> Map.put(:line_width, 1)
    |> Contex.Sparkline.colours("#ad958f", "#f2ebe4")
    |> Contex.Sparkline.draw()
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
