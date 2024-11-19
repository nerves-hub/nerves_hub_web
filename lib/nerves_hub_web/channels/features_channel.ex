defmodule NervesHubWeb.FeaturesChannel do
  use Phoenix.Channel

  alias Phoenix.Socket.Broadcast
  alias NervesHub.Devices
  alias NervesHub.Features
  alias NervesHub.Devices.Metrics

  require Logger

  @impl Phoenix.Channel
  def join("features", feature_versions, socket) do
    features = parse_features(socket.assigns.device, feature_versions)
    socket = assign(socket, :features, features)

    attach_list = for {key, %{attach?: true}} <- features, do: key

    if length(attach_list) > 0 do
      send(self(), :init_features)
    end

    topic = "device:#{socket.assigns.device.id}:features"
    NervesHubWeb.DeviceEndpoint.subscribe(topic)

    # feature_config = Application.get_env(:nerves_hub, :feature_config, [])

    # maybe_configure_geo(attach_list, feature_config)
    # maybe_configure_health(attach_list, feature_config)

    {:ok, attach_list, socket}
  end

  import Ecto.Query

  defp parse_features(
         %{features: device_features, product: %{features: product_features}},
         feature_versions
       ) do
    keys = Map.keys(feature_versions)

    allowed_features =
      product_features
      |> Map.from_struct()
      |> Enum.filter(fn {feature, enabled?} ->
        enabled? == true and Map.get(device_features, feature) != false
      end)
      |> Enum.map(&elem(&1, 0))

    for {key_str, version} <- feature_versions, into: %{} do
      meta =
        case Version.parse(version) do
          {:ok, ver} ->
            feature = Enum.find(allowed_features, &(to_string(&1) == key_str))

            if feature do
              mod = feature_module(feature, ver)
              %{attach?: Code.ensure_loaded?(mod), version: ver, module: mod, status: :detached}
            else
              %{attach?: false, version: version, module: nil, status: :detached}
            end

          _ ->
            %{attach?: false, version: version, module: nil, status: :detached}
        end

      {key_str, meta}
    end
  end

  defp feature_module(:health, ver) do
    cond do
      Version.match?(ver, "~> 0.0.1") -> NervesHub.Features.Health
      true -> :unsupported
    end
  end

  defp feature_module(:geo, ver) do
    cond do
      Version.match?(ver, "~> 0.0.1") -> NervesHub.Features.Geo
      true -> :unsupported
    end
  end

  defp feature_module(key, _ver) do
    :unsupported
  end

  # defp allowed?(device, feature, version) do
  #   Features.enable_feature?(device, feature, version)
  # end

  @impl Phoenix.Channel
  def handle_in(scoped_event, payload, socket) do
    socket =
      with [key, event] <- String.split(scoped_event, ":", parts: 2),
           # mappings = Ecto.Enum.mappings(NervesHub.Features.Feature, :key),
           # key = Enum.find_value(mappings, fn {key, val} -> val == key_str && key end),
           %{attach?: true, module: mod} <- socket.assigns.features[key] do
        case event do
          "attached" ->
            update_in(socket.assigns.features[key], &%{&1 | status: :attached})
            |> mod.attach()

          "detached" ->
            update_in(socket.assigns.features[key], &%{&1 | status: :detached})
            |> mod.detach()

          "error" ->
            socket = update_in(socket.assigns.features[key], &%{&1 | status: :detached})
            safe_handle_in(mod, event, payload, socket)

          event ->
            safe_handle_in(mod, event, payload, socket)
        end
      else
        _ ->
          # Unknown feature, tell device to detach it
          {:reply, {:error, "detach"}, socket}
      end
  end

  # def handle_in("geo:location:update", location, %{assigns: %{device: device}} = socket) do
  #   metadata = Map.put(device.connection_metadata, "location", location)

  #   {:ok, device} = Devices.update_device(device, %{connection_metadata: metadata})

  #   _ =
  #     NervesHubWeb.DeviceEndpoint.broadcast(
  #       "device:#{device.identifier}:internal",
  #       "location:updated",
  #       location
  #     )

  #   {:noreply, assign(socket, :device, device)}
  # end

  # def handle_in("health:report", %{"value" => device_status}, socket) do
  #   device_meta =
  #     for {key, val} <- Map.from_struct(socket.assigns.device.firmware_metadata),
  #         into: %{},
  #         do: {to_string(key), to_string(val)}

  #   # Separate metrics from health report to store in metrics table
  #   metrics = device_status["metrics"]

  #   health_report =
  #     device_status
  #     |> Map.delete("metrics")
  #     |> Map.put("metadata", Map.merge(device_status["metadata"], device_meta))

  #   device_health = %{"device_id" => socket.assigns.device.id, "data" => health_report}

  #   with {:health_report, {:ok, _}} <-
  #          {:health_report, Devices.save_device_health(device_health)},
  #        {:metrics_report, {:ok, _}} <-
  #          {:metrics_report, Metrics.save_metrics(socket.assigns.device.id, metrics)} do
  #     device_internal_broadcast!(socket.assigns.device, "health_check_report", %{})
  #   else
  #     {:health_report, {:error, err}} ->
  #       Logger.warning("Failed to save health check data: #{inspect(err)}")
  #       log_to_sentry(socket.assigns.device, "[DeviceChannel] Failed to save health check data.")

  #     {:metrics_report, {:error, err}} ->
  #       Logger.warning("Failed to save metrics: #{inspect(err)}")
  #       log_to_sentry(socket.assigns.device, "[DeviceChannel] Failed to save metrics.")
  #   end

  #   {:noreply, socket}
  # end

  def handle_in(event, payload, socket) do
    Logger.info("Unhandled message '#{event}': #{inspect(payload)}")
    {:noreply, socket}
  end

  defp safe_handle_in(mod, event, payload, socket) do
    mod.handle_in(event, payload, socket)
  rescue
    error ->
      Logger.warning("#{inspect(mod)} failed to handle feature message - #{inspect(error)}")
      log_to_sentry(socket.assigns.device, error)
      {:noreply, socket}
  end

  @impl Phoenix.Channel
  def handle_info(:init_features, socket) do
    topic = "product:#{socket.assigns.device.product.id}:features"
    NervesHubWeb.DeviceEndpoint.subscribe(topic)

    socket =
      for {feature, %{attach?: true, mod: mod}} <- socket.assigns.features, reduce: socket do
        acc ->
          mod.init(acc)
      end

    {:noreply, socket}
  end

  def handle_info(%Broadcast{event: event, payload: payload}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  def handle_info({mod, msg}, socket) do
    mod.handle_info(msg, socket)
  rescue
    error ->
      Logger.warning("#{inspect(mod)} failed handle_info - #{inspect(error)}")
      log_to_sentry(socket.assigns.device, error)
      {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # def handle_info(:geo_request, socket) do
  #   push(socket, "geo:location:request", %{})
  #   {:noreply, socket}
  # end

  # def handle_info(:health_check, socket) do
  #   push(socket, "health:check", %{})
  #   {:noreply, socket}
  # end

  # defp maybe_configure_geo(attach_list, feature_config) do
  #   # if a geo interval is configured, set up an interval
  #   geo_interval = get_in(feature_config, [:geo, :interval_minutes]) || 0

  #   if attach_list[:geo] do
  #     send(self(), :geo_request)

  #     if geo_interval > 0 do
  #       geo_interval
  #       |> :timer.minutes()
  #       |> :timer.send_interval(:geo_request)
  #     end
  #   end
  # end

  # defp maybe_configure_health(attach_list, feature_config) do
  #   health_interval = get_in(feature_config, [:health, :interval_minutes]) || 60

  #   if attach_list[:health] do
  #     send(self(), :health_check)

  #     if health_interval > 0 do
  #       health_interval
  #       |> :timer.minutes()
  #       |> :timer.send_interval(:health_check)
  #     end
  #   end
  # end

  # defp device_internal_broadcast!(device, event, payload) do
  #   topic = "device:#{device.identifier}:features"
  #   NervesHubWeb.DeviceEndpoint.broadcast_from!(self(), topic, event, payload)
  # end

  defp log_to_sentry(device, msg_or_ex, extra \\ %{}) do
    Sentry.Context.set_tags_context(%{
      device_identifier: device.identifier,
      device_id: device.id,
      product_id: device.product_id,
      org_id: device.org_id
    })

    _ =
      if is_exception(msg_or_ex) do
        Sentry.capture_exception(msg_or_ex, extra: extra, result: :none)
      else
        Sentry.capture_message(msg_or_ex, extra: extra, result: :none)
      end

    :ok
  end
end
