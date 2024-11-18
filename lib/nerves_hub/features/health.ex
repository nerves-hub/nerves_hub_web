defmodule NervesHub.Features.Health do
  @behaviour NervesHub.Features

  alias NervesHub.Devices
  alias NervesHub.Devices.Metrics

  # @impl NervesHub.Features
  def init(socket) do
    # Allow DB settings?
    socket
  end

  def attach(socket) do
    feature_config = Application.get_env(:nerves_hub, :feature_config, [])

    health_interval =
      case get_in(feature_config, [:health, :interval_minutes]) do
        i when is_integer(i) -> i
        _ -> 60
      end

    send(self(), {__MODULE__, :check})

    socket =
      if health_interval > 0 do
        timer =
          health_interval
          |> :timer.minutes()
          |> :timer.send_interval({__MODULE__, :check})

        socket
        |> Phoenix.Socket.assign(:health_interval, health_interval)
        |> Phoenix.Socket.assign(:health_timer, timer)
      else
        socket
      end

    {:noreply, socket}
  end

  def detach(socket) do
    _ = if socket.assigns[:health_timer], do: :timer.cancel(socket.assigns.health_timer)
    {:noreply, Phoenix.Socket.assign(socket, :health_timer, nil)}
  end

  @impl NervesHub.Features
  def handle_in("report", %{"value" => device_status}, socket) do
    device_meta =
      for {key, val} <- Map.from_struct(socket.assigns.device.firmware_metadata),
          into: %{},
          do: {to_string(key), to_string(val)}

    # Separate metrics from health report to store in metrics table
    metrics = device_status["metrics"]

    health_report =
      device_status
      |> Map.delete("metrics")
      |> Map.put("metadata", Map.merge(device_status["metadata"], device_meta))

    device_health = %{"device_id" => socket.assigns.device.id, "data" => health_report}

    with {:health_report, {:ok, _}} <-
           {:health_report, Devices.save_device_health(device_health)},
         {:metrics_report, {count, _}} when count >= 0 <-
           {:metrics_report, Metrics.save_metrics(socket.assigns.device.id, metrics)} do
      device_internal_broadcast!(socket.assigns.device, "health_check_report", %{})
    else
      {:health_report, {:error, err}} ->
        Logger.warning("Failed to save health check data: #{inspect(err)}")

      # log_to_sentry(socket.assigns.device, "[DeviceChannel] Failed to save health check data.")

      {:metrics_report, {:error, err}} ->
        Logger.warning("Failed to save metrics: #{inspect(err)}")
        # log_to_sentry(socket.assigns.device, "[DeviceChannel] Failed to save metrics.")
    end

    {:noreply, socket}
  end

  @impl NervesHub.Features
  def handle_info(:check, socket) do
    Phoenix.Channel.push(socket, "health:check", %{})
    {:noreply, socket}
  end

  defp device_internal_broadcast!(device, event, payload) do
    topic = "device:#{device.identifier}:features"
    NervesHubWeb.DeviceEndpoint.broadcast_from!(self(), topic, event, payload)
  end
end
