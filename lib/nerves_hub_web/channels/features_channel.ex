defmodule NervesHubWeb.FeaturesChannel do
  use Phoenix.Channel

  alias Phoenix.Socket.Broadcast
  alias NervesHub.Devices
  alias NervesHub.Features
  alias NervesHub.Devices.Metrics

  require Logger

  @impl Phoenix.Channel
  def join("features", payload, socket) do
    attach_list =
      for {feature, ver} <- payload, into: %{} do
        feature = String.to_existing_atom(feature)
        {feature, allowed?(socket.assigns.device, feature, ver)}
      end

    topic = "device:#{socket.assigns.device.id}:features"
    NervesHubWeb.DeviceEndpoint.subscribe(topic)

    feature_config = Application.get_env(:nerves_hub, :feature_config, [])

    maybe_configure_geo(attach_list, feature_config)
    maybe_configure_health(attach_list, feature_config)

    {:ok, attach_list, socket}
  end

  defp allowed?(device, feature, version) do
    Features.enable_feature?(device, feature, version)
  end

  @impl Phoenix.Channel
  def handle_in("geo:location:update", location, %{assigns: %{device: device}} = socket) do
    metadata = Map.put(device.connection_metadata, "location", location)

    {:ok, device} = Devices.update_device(device, %{connection_metadata: metadata})

    _ =
      NervesHubWeb.DeviceEndpoint.broadcast(
        "device:#{device.identifier}:internal",
        "location:updated",
        location
      )

    {:noreply, assign(socket, :device, device)}
  end

  def handle_in("health:report", %{"value" => device_status}, socket) do
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
         {:metrics_report, {:ok, _}} <-
           {:metrics_report, Metrics.save_metrics(socket.assigns.device.id, metrics)} do
      device_internal_broadcast!(socket.assigns.device, "health_check_report", %{})
    else
      {:health_report, {:error, err}} ->
        Logger.warning("Failed to save health check data: #{inspect(err)}")
        log_to_sentry(socket.assigns.device, "[DeviceChannel] Failed to save health check data.")

      {:metrics_report, {:error, err}} ->
        Logger.warning("Failed to save metrics: #{inspect(err)}")
        log_to_sentry(socket.assigns.device, "[DeviceChannel] Failed to save metrics.")
    end

    {:noreply, socket}
  end

  def handle_in(event, payload, socket) do
    Logger.info("Unhandled message '#{event}': #{inspect(payload)}")
    {:noreply, socket}
  end

  @impl Phoenix.Channel
  def handle_info(%Broadcast{event: event, payload: payload}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  def handle_info(:geo_request, socket) do
    push(socket, "geo:location:request", %{})
    {:noreply, socket}
  end

  def handle_info(:health_check, socket) do
    push(socket, "health:check", %{})
    {:noreply, socket}
  end

  defp maybe_configure_geo(attach_list, feature_config) do
    # if a geo interval is configured, set up an interval
    geo_interval = get_in(feature_config, [:geo, :interval_minutes]) || 0

    if attach_list[:geo] do
      send(self(), :geo_request)

      if geo_interval > 0 do
        geo_interval
        |> :timer.minutes()
        |> :timer.send_interval(:geo_request)
      end
    end
  end

  defp maybe_configure_health(attach_list, feature_config) do
    health_interval = get_in(feature_config, [:health, :interval_minutes]) || 60

    if attach_list[:health] do
      send(self(), :health_check)

      if health_interval > 0 do
        health_interval
        |> :timer.minutes()
        |> :timer.send_interval(:health_check)
      end
    end
  end

  defp device_internal_broadcast!(device, event, payload) do
    topic = "device:#{device.identifier}:features"
    NervesHubWeb.DeviceEndpoint.broadcast_from!(self(), topic, event, payload)
  end

  defp log_to_sentry(device, message, extra \\ %{}) do
    Sentry.Context.set_tags_context(%{
      device_identifier: device.identifier,
      device_id: device.id,
      product_id: device.product_id,
      org_id: device.org_id
    })

    _ = Sentry.capture_message(message, extra: extra, result: :none)

    :ok
  end
end
