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
    |> assign_metrics()
    |> ok()
  end

  def handle_info(%Broadcast{event: "health_check_report"}, socket) do
    socket
    |> assign_metrics()
    |> noreply()
  end

  # Ignore other events for now
  def handle_info(_event, socket), do: {:noreply, socket}

  def assign_metrics(socket) do
    metrics = Devices.get_device_metrics(socket.assigns.device.id)

    IO.inspect(metrics.size_mb)

    socket
    |> assign(:cpu_temp, create_sparkline_svg(metrics.cpu_temp))
    |> assign(:load_1min, create_sparkline_svg(metrics.load_1min))
    |> assign(:load_5min, create_sparkline_svg(metrics.load_5min))
    |> assign(:load_15min, create_sparkline_svg(metrics.load_15min))
    |> assign(:used_mb, create_sparkline_svg(metrics.used_mb))
    |> assign(:used_percent, create_sparkline_svg(metrics.used_percent))
  end

  defp create_sparkline_svg(metrics) when is_list(metrics) do
    metrics
    |> Contex.Sparkline.new()
    |> Map.put(:width, 500)
    |> Map.put(:height, 200)
    |> Map.put(:line_width, 1)
    |> Contex.Sparkline.colours("#ad958f", "#f2ebe4")
    |> Contex.Sparkline.draw()
  end



end
