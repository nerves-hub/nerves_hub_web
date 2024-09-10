defmodule NervesHubWeb.DeviceChannel do
  @moduledoc """
  Primary websocket channel for device communication

  Handles device logic for updating and tracking devices
  """

  use Phoenix.Channel

  require Logger

  alias NervesHub.Archives
  alias NervesHub.AuditLogs
  alias NervesHub.Deployments
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.Metrics
  alias NervesHub.Firmwares
  alias NervesHub.Repo
  alias NervesHub.Tracker
  alias Phoenix.Socket.Broadcast

  def join("device", params, %{assigns: %{device: device}} = socket) do
    with {:ok, device} <- update_metadata(device, params),
         {:ok, device} <- Devices.device_connected(device) do
      socket = assign(socket, :device, device)

      send(self(), {:after_join, params})

      {:ok, socket}
    else
      err ->
        Logger.warning("[DeviceChannel] failure to connect - #{inspect(err)}")
        _ = Devices.device_disconnected(device)
        {:error, %{error: "could not connect"}}
    end
  end

  def handle_info({:after_join, params}, %{assigns: %{device: device}} = socket) do
    socket = assign(socket, :device_api_version, Map.get(params, "device_api_version", "1.0.0"))

    device =
      device
      |> Devices.verify_deployment()
      |> Deployments.set_deployment()
      |> Repo.preload(:org)
      |> deployment_preload()

    if params["fwup_public_keys"] == "on_connect" do
      send_public_keys(device, socket, "fwup_public_keys")
    end

    if params["archive_public_keys"] == "on_connect" do
      send_public_keys(device, socket, "archive_public_keys")
    end

    # clear out any inflight updates, there shouldn't be one at this point
    # we might make a new one right below it, so clear it beforehand
    Devices.clear_inflight_update(device)

    # Let the orchestrator handle this going forward ?
    update_payload = Devices.resolve_update(device)

    push_update? =
      update_payload.update_available and not is_nil(update_payload.firmware_url) and
        update_payload.firmware_meta[:uuid] != params["currently_downloading_uuid"]

    maybe_push_update(socket, update_payload, device, push_update?)

    ## After join
    :telemetry.execute([:nerves_hub, :devices, :connect], %{count: 1}, %{
      ref_id: socket.assigns.reference_id,
      identifier: device.identifier,
      firmware_uuid: device.firmware_metadata.uuid
    })

    # local node tracking
    _ =
      Registry.update_value(NervesHub.Devices, device.id, fn value ->
        update = %{
          deployment_id: device.deployment_id,
          firmware_uuid: device.firmware_metadata.uuid,
          updates_enabled: device.updates_enabled && !Devices.device_in_penalty_box?(device),
          updating: push_update?
        }

        Map.merge(value, update)
      end)

    # Cluster tracking
    Tracker.online(device)

    socket =
      socket
      |> assign(:device, device)
      |> assign(:update_started?, push_update?)
      |> assign(:penalty_timer, nil)
      |> maybe_start_penalty_timer()
      |> maybe_send_archive()

    send(self(), :boot)

    if device_health_check_enabled?() do
      send(self(), :health_check)
      schedule_health_check()
    end

    {:noreply, socket}
  end

  def handle_info(:boot, %{assigns: %{device: device}} = socket) do
    ref_id = Base.encode32(:crypto.strong_rand_bytes(2), padding: false)

    deployment_channel =
      if device.deployment_id do
        "deployment:#{device.deployment_id}"
      else
        "deployment:none"
      end

    subscribe("device:#{device.id}")
    subscribe(deployment_channel)

    # local node tracking
    _ =
      Registry.register(NervesHub.Devices, device.id, %{
        deployment_id: device.deployment_id,
        firmware_uuid: get_in(device, [Access.key(:firmware_metadata), Access.key(:uuid)]),
        updates_enabled: device.updates_enabled && !Devices.device_in_penalty_box?(device),
        updating: false
      })

    Process.send_after(self(), :update_connection_last_seen, last_seen_update_interval())

    socket =
      socket
      |> assign(:device, device)
      |> assign(:deployment_channel, deployment_channel)
      |> assign(:reference_id, ref_id)

    {:noreply, socket}
  end

  def handle_info(:update_connection_last_seen, %{assigns: %{device: device}} = socket) do
    {:ok, _device} = Devices.device_heartbeat(device)

    device_broadcast(device, "connection:heartbeat")

    Process.send_after(self(), :update_connection_last_seen, last_seen_update_interval())

    {:noreply, socket}
  end

  # We can save a fairly expensive query by checking the incoming deployment's payload
  # If it matches, we can set the deployment directly and only do 3 queries (update, two preloads)
  def handle_info(
        %Broadcast{event: "deployments/changed", topic: "deployment:none", payload: payload},
        %{assigns: %{device: device}} = socket
      ) do
    if device_matches_deployment_payload?(device, payload) do
      cancel_deployment_timer(socket)

      # jitter to attempt to not slam the database when any matching
      # devices go to set their deployment. This is for very large
      # deployments, to prevent ecto pool contention.
      jitter = device_deployment_change_jitter_ms()
      timer = Process.send_after(self(), {:assign_deployment, payload}, jitter)
      {:noreply, assign(socket, :assign_deployment_timer, timer)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:assign_deployment, payload}, socket) do
    socket = assign(socket, :assign_deployment_timer, nil)
    {:noreply, assign_deployment(socket, payload)}
  end

  def handle_info(
        %Broadcast{event: "deployments/changed", payload: payload},
        %{assigns: %{device: device}} = socket
      ) do
    if device_matches_deployment_payload?(device, payload) do
      :telemetry.execute([:nerves_hub, :devices, :deployment, :changed], %{count: 1})
      {:noreply, assign_deployment(socket, payload)}
    else
      # jitter to attempt to not slam the database when any matching
      # devices go to set their deployment. This is for very large
      # deployments, to prevent ecto pool contention.
      jitter = device_deployment_change_jitter_ms()
      Process.send_after(self(), :resolve_changed_deployment, jitter)
      {:noreply, socket}
    end
  end

  def handle_info(:resolve_changed_deployment, %{assigns: %{device: device}} = socket) do
    :telemetry.execute([:nerves_hub, :devices, :deployment, :changed], %{count: 1})

    device =
      device
      |> Repo.reload()
      |> Deployments.set_deployment()
      |> deployment_preload()

    description =
      if device.deployment_id do
        "device #{device.identifier} reloaded deployment and is attached to deployment #{device.deployment.name}"
      else
        "device #{device.identifier} reloaded deployment and is no longer attached to a deployment"
      end

    AuditLogs.audit_with_ref!(
      device,
      device,
      description,
      socket.assigns.reference_id
    )

    _ =
      Registry.update_value(NervesHub.Devices, device.id, fn value ->
        Map.put(value, :deployment_id, device.deployment_id)
      end)

    socket =
      socket
      |> update_device(device)
      |> maybe_send_archive()

    {:noreply, socket}
  end

  # manually pushed
  def handle_info(%Broadcast{event: "devices/update-manual", payload: payload}, socket) do
    :telemetry.execute([:nerves_hub, :devices, :update, :manual], %{count: 1})
    push(socket, "update", payload)
    {:noreply, socket}
  end

  def handle_info(%Broadcast{event: "deployments/update"}, socket) do
    {:noreply, socket}
  end

  def handle_info({"deployments/update", inflight_update}, %{assigns: %{device: device}} = socket) do
    device = deployment_preload(device)

    payload = Devices.resolve_update(device)

    case payload.update_available do
      true ->
        :telemetry.execute([:nerves_hub, :devices, :update, :automatic], %{count: 1}, %{
          identifier: device.identifier,
          firmware_uuid: inflight_update.firmware_uuid
        })

        deployment = device.deployment
        firmware = deployment.firmware

        description =
          "deployment #{deployment.name} update triggered device #{device.identifier} to update firmware #{firmware.uuid}"

        # If we get here, the device is connected and high probability it receives
        # the update message so we can Audit and later assert on this audit event
        # as a loosely valid attempt to update
        AuditLogs.audit_with_ref!(
          deployment,
          device,
          description,
          socket.assigns.reference_id
        )

        Devices.update_started!(inflight_update)
        push(socket, "update", payload)

        {:noreply, socket}

      false ->
        {:noreply, socket}
    end
  end

  def handle_info(%Broadcast{event: "archives/updated"}, socket) do
    device = deployment_preload(socket.assigns.device)

    socket =
      socket
      |> assign(:device, device)
      |> maybe_send_archive()

    {:noreply, socket}
  end

  def handle_info(%Broadcast{event: "moved"}, socket) do
    # The old deployment is no longer valid, so let's look one up again
    handle_info(:resolve_changed_deployment, socket)
  end

  # Update local state and tell the various servers of the new information
  def handle_info(%Broadcast{event: "devices/updated"}, %{assigns: %{device: device}} = socket) do
    device = Repo.reload(device)

    _ =
      Registry.update_value(NervesHub.Devices, device.id, fn value ->
        Map.merge(value, %{
          updates_enabled: device.updates_enabled && !Devices.device_in_penalty_box?(device)
        })
      end)

    socket =
      socket
      |> update_device(device)
      |> maybe_start_penalty_timer()
      |> maybe_send_archive()

    {:noreply, socket}
  end

  def handle_info(:online?, socket) do
    NervesHub.Tracker.confirm_online(socket.assigns.device)
    {:noreply, socket}
  end

  def handle_info({:online?, pid}, socket) do
    send(pid, :online)
    {:noreply, socket}
  end

  def handle_info({:run_script, pid, text}, socket) do
    if Version.match?(socket.assigns.device_api_version, ">= 2.1.0") do
      ref = Base.encode64(:crypto.strong_rand_bytes(4), padding: false)

      push(socket, "scripts/run", %{"text" => text, "ref" => ref})

      script_refs =
        socket.assigns
        |> Map.get(:script_refs, %{})
        |> Map.put(ref, pid)

      socket = assign(socket, :script_refs, script_refs)

      Process.send_after(self(), {:clear_script_ref, ref}, 15_000)

      {:noreply, socket}
    else
      send(pid, {:error, :incompatible_version})

      {:noreply, socket}
    end
  end

  def handle_info({:clear_script_ref, ref}, socket) do
    Logger.info("[DeviceChannel] clearing ref #{ref}")

    script_refs =
      socket.assigns
      |> Map.get(:script_refs, %{})
      |> Map.delete(ref)

    socket = assign(socket, :script_refs, script_refs)

    {:noreply, socket}
  end

  def handle_info(%Broadcast{event: event, payload: payload}, socket) do
    # Forward broadcasts to the device for now
    push(socket, event, payload)
    {:noreply, socket}
  end

  def handle_info(:penalty_box_check, %{assigns: %{device: device}} = socket) do
    updates_enabled = device.updates_enabled && !Devices.device_in_penalty_box?(device)

    :telemetry.execute([:nerves_hub, :devices, :penalty_box, :check], %{
      updates_enabled: updates_enabled
    })

    _ =
      Registry.update_value(NervesHub.Devices, device.id, fn value ->
        Map.merge(value, %{updates_enabled: updates_enabled})
      end)

    # Just in case time is weird or it got placed back in between checks
    if updates_enabled do
      {:noreply, socket}
    else
      {:noreply, maybe_start_penalty_timer(socket)}
    end
  end

  def handle_info({:push, event, payload}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  def handle_info(:health_check, socket) do
    push(socket, "check_health", %{})
    schedule_health_check()
    {:noreply, socket}
  end

  def handle_info(%Broadcast{event: "connection:heartbeat"}, socket) do
    # Expected message that is not used here :)
    {:noreply, socket}
  end

  def handle_info(msg, socket) do
    # Ignore unhandled messages so that it doesn't crash the link process
    # preventing cascading problems.
    Logger.warning("[DeviceChannel] Unhandled handle_info message! - #{inspect(msg)}")

    log_to_sentry(socket.assigns.device, "[DeviceChannel] Unhandled handle_info message!", %{
      message: msg
    })

    {:noreply, socket}
  end

  def handle_in("fwup_progress", %{"value" => percent}, %{assigns: %{device: device}} = socket) do
    NervesHubWeb.DeviceEndpoint.broadcast_from!(
      self(),
      "device:#{device.identifier}:internal",
      "fwup_progress",
      %{
        percent: percent
      }
    )

    # if this is the first fwup we see, then mark it as an update attempt
    if socket.assigns.update_started? do
      {:noreply, socket}
    else
      # reload update attempts because they might have been cleared
      # and we have a cached stale version
      updated_device = Repo.reload(device)
      device = %{device | update_attempts: updated_device.update_attempts}

      {:ok, device} = Devices.update_attempted(device)

      _ =
        Registry.update_value(NervesHub.Devices, device.id, fn value ->
          Map.put(value, :updating, true)
        end)

      socket =
        socket
        |> assign(:device, deployment_preload(device))
        |> assign(:update_started?, true)

      {:noreply, socket}
    end
  end

  def handle_in("location:update", location, %{assigns: %{device: device}} = socket) do
    metadata = Map.put(device.connection_metadata, "location", location)

    {:ok, device} = Devices.update_device(device, %{connection_metadata: metadata})

    _ =
      NervesHubWeb.DeviceEndpoint.broadcast(
        "device:#{device.identifier}:internal",
        "location:updated",
        location
      )

    {:reply, :ok, assign(socket, :device, device)}
  end

  def handle_in("connection_types", %{"values" => types}, %{assigns: %{device: device}} = socket) do
    {:ok, device} = Devices.update_device(device, %{"connection_types" => types})
    {:noreply, assign(socket, :device, device)}
  end

  def handle_in("status_update", %{"status" => _status}, socket) do
    # TODO store in tracker or the database?
    {:noreply, socket}
  end

  def handle_in("check_update_available", _params, socket) do
    device =
      socket.assigns.device
      |> Devices.verify_deployment()
      |> Deployments.set_deployment()
      |> Repo.preload(:org)
      |> Repo.preload(deployment: [:archive, :firmware])

    # Let the orchestrator handle this going forward ?
    update_payload = Devices.resolve_update(device)

    {:reply, {:ok, update_payload}, socket}
  end

  def handle_in("rebooting", _, socket) do
    {:noreply, socket}
  end

  def handle_in("scripts/run", params, socket) do
    if pid = socket.assigns.script_refs[params["ref"]] do
      output = Enum.join([params["output"], params["return"]], "\n")
      output = String.trim(output)
      send(pid, {:output, output})
    end

    {:noreply, socket}
  end

  def handle_in("health_check_report", %{"value" => device_status}, socket) do
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
      NervesHubWeb.DeviceEndpoint.broadcast_from!(
        self(),
        "device:#{socket.assigns.device.identifier}:internal",
        "health_check_report",
        %{}
      )
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

  def handle_in(msg, params, socket) do
    # Ignore unhandled messages so that it doesn't crash the link process
    # preventing cascading problems.
    Logger.warning(
      "[DeviceChannel] Unhandled handle_in message! - #{inspect(msg)} - #{inspect(params)}"
    )

    device = socket.assigns.device
    log_to_sentry(device, "[DeviceChannel] Unhandled message!", %{message: msg})

    {:noreply, socket}
  end

  def terminate(_reason, %{assigns: %{device: device}} = socket) do
    :telemetry.execute([:nerves_hub, :devices, :disconnect], %{count: 1}, %{
      ref_id: socket.assigns.reference_id,
      identifier: device.identifier
    })

    {:ok, device} = Devices.device_disconnected(device)

    Registry.unregister(NervesHub.Devices, device.id)

    Tracker.offline(device)

    :ok
  end

  defp log_to_sentry(device, message, extra \\ %{}) do
    Sentry.Context.set_tags_context(%{
      device_identifier: device.identifier,
      device_id: device.id,
      product_id: device.product_id,
      org_id: device.org_id
    })

    _ =
      Sentry.capture_message(message,
        extra: extra,
        result: :none
      )
  end

  defp maybe_push_update(_socket, _update_payload, _device, false) do
    :ok
  end

  defp maybe_push_update(socket, update_payload, device, true) do
    # Push the update to the device
    push(socket, "update", update_payload)

    deployment = device.deployment

    description =
      "device #{device.identifier} received update for firmware #{deployment.firmware.version}(#{deployment.firmware.uuid}) via deployment #{deployment.name} on connect"

    AuditLogs.audit_with_ref!(
      deployment,
      device,
      description,
      socket.assigns.reference_id
    )

    # if there's an update, track it
    _ = Devices.told_to_update(device, deployment)

    :ok
  end

  defp subscribe(topic) do
    _ = Phoenix.PubSub.subscribe(NervesHub.PubSub, topic)
    :ok
  end

  defp unsubscribe(topic) do
    Phoenix.PubSub.unsubscribe(NervesHub.PubSub, topic)
  end

  defp device_broadcast(device, event, payload \\ %{}) do
    topic = "device:#{device.identifier}:internal"
    _ = NervesHubWeb.DeviceEndpoint.broadcast(topic, event, payload)
    :ok
  end

  defp send_public_keys(device, socket, key_type) do
    org_keys = NervesHub.Accounts.list_org_keys(device.org)

    push(socket, key_type, %{
      keys: Enum.map(org_keys, fn ok -> ok.key end)
    })
  end

  defp cancel_deployment_timer(%{assigns: %{assign_deployment_timer: timer}}) do
    _ = Process.cancel_timer(timer)
    :ok
  end

  defp cancel_deployment_timer(_socket) do
    :ok
  end

  # The reported firmware is the same as what we already know about
  defp update_metadata(%Device{firmware_metadata: %{uuid: uuid}} = device, %{
         "nerves_fw_uuid" => uuid
       }) do
    {:ok, device}
  end

  # A new UUID is being reported from an update
  defp update_metadata(device, params) do
    with {:ok, metadata} <- Firmwares.metadata_from_device(params),
         {:ok, device} <- Devices.update_firmware_metadata(device, metadata) do
      Devices.firmware_update_successful(device)
    end
  end

  defp maybe_start_penalty_timer(%{assigns: %{device: %{updates_blocked_until: nil}}} = socket),
    do: socket

  defp maybe_start_penalty_timer(socket) do
    check_penalty_box_in =
      DateTime.diff(socket.assigns.device.updates_blocked_until, DateTime.utc_now(), :millisecond)

    ref =
      if check_penalty_box_in > 0 do
        _ =
          if socket.assigns.penalty_timer, do: Process.cancel_timer(socket.assigns.penalty_timer)

        # delay the check slightly to make sure the penalty is cleared when its updated
        Process.send_after(self(), :penalty_box_check, check_penalty_box_in + 1000)
      end

    assign(socket, :penalty_timer, ref)
  end

  defp device_matches_deployment_payload?(device, payload) do
    payload.active &&
      device.product_id == payload.product_id &&
      device.firmware_metadata.platform == payload.platform &&
      device.firmware_metadata.architecture == payload.architecture &&
      Enum.all?(payload.conditions["tags"], &Enum.member?(device.tags, &1)) &&
      Deployments.version_match?(device, payload)
  end

  defp assign_deployment(%{assigns: %{device: device}} = socket, payload) do
    device =
      device
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_change(:deployment_id, payload.id)
      |> Repo.update!()
      |> deployment_preload()

    description =
      "device #{device.identifier} reloaded deployment and is attached to deployment #{device.deployment.name}"

    AuditLogs.audit_with_ref!(device, device, description, socket.assigns.reference_id)

    _ =
      Registry.update_value(NervesHub.Devices, device.id, fn value ->
        Map.put(value, :deployment_id, device.deployment_id)
      end)

    socket
    |> update_device(device)
    |> maybe_send_archive()
  end

  defp update_device(socket, device) do
    socket
    |> assign(:device, deployment_preload(device))
    |> update_deployment_subscription(device)
  end

  defp update_deployment_subscription(socket, device) do
    deployment_channel =
      if device.deployment_id do
        "deployment:#{device.deployment_id}"
      else
        "deployment:none"
      end

    if deployment_channel != socket.assigns.deployment_channel do
      unsubscribe(socket.assigns.deployment_channel)
      subscribe(deployment_channel)
      assign(socket, :deployment_channel, deployment_channel)
    else
      socket
    end
  end

  defp device_deployment_change_jitter_ms() do
    jitter = Application.get_env(:nerves_hub, :device_deployment_change_jitter_seconds)
    :rand.uniform(jitter) * 1000
  end

  defp schedule_health_check() do
    if device_health_check_enabled?() do
      interval = Application.get_env(:nerves_hub, :device_health_check_interval_minutes)
      Process.send_after(self(), :health_check, :timer.minutes(interval))
      :ok
    else
      :ok
    end
  end

  defp last_seen_update_interval() do
    Application.get_env(:nerves_hub, :device_last_seen_update_interval_minutes)
    |> :timer.minutes()
  end

  defp device_health_check_enabled?() do
    Application.get_env(:nerves_hub, :device_health_check_enabled)
  end

  defp deployment_preload(device) do
    Repo.preload(device, [deployment: [:archive, :firmware]], force: true)
  end

  defp maybe_send_archive(socket) do
    device = socket.assigns.device

    updates_enabled = device.updates_enabled && !Devices.device_in_penalty_box?(device)
    version_match = Version.match?(socket.assigns.device_api_version, ">= 2.0.0")

    if updates_enabled && version_match do
      if device.deployment && device.deployment.archive do
        archive = device.deployment.archive

        push(socket, "archive", %{
          size: archive.size,
          uuid: archive.uuid,
          version: archive.version,
          description: archive.description,
          platform: archive.platform,
          architecture: archive.architecture,
          uploaded_at: archive.inserted_at,
          url: Archives.url(archive)
        })
      end
    end

    socket
  end
end
