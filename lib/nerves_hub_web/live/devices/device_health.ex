defmodule NervesHubWeb.Live.Devices.DeviceHealth do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Devices
  alias NervesHub.Tracker

  alias NervesHubWeb.Components.HealthHeader
  alias NervesHubWeb.Components.HealthSection

  alias Phoenix.Socket.Broadcast

  @check_health_interval 1_000
  @time_frame_opts [
    {"hour", 1},
    {"day", 1},
    {"day", 7}
  ]
  @default_time_frame {"hour", 1}

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
    |> assign(:time_frame, @default_time_frame)
    |> assign(:time_frame_opts, @time_frame_opts)
    # TODO: Make sure health reports are coming in correctly from channel
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

  defp assign_metrics(%{assigns: %{device: device, time_frame: {unit, amount}}} = socket) do
    metrics =
      Devices.get_device_metrics(device.id, unit, amount)

    socket
    |> assign(:cpu_temp_line_plot, create_line_plot_svg(metrics.cpu_temp))
    |> assign(:load_1min_line_plot, create_line_plot_svg(metrics.load_1min))
    |> assign(:load_5min_line_plot, create_line_plot_svg(metrics.load_5min))
    |> assign(:load_15min_line_plot, create_line_plot_svg(metrics.load_15min))
    |> assign(:used_mb_line_plot, create_line_plot_svg(metrics.used_mb))
    |> assign(:used_percent_line_plot, create_line_plot_svg(metrics.used_percent))
  end

  defp create_line_plot_svg(data) do
    if(data == []) do
      "No data for selected period"
    else
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
