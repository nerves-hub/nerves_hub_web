defmodule NervesHubWeb.DeviceChannel do
  @moduledoc """
  Primary websocket channel for device communication

  Handles device logic for updating and tracking devices
  """

  use Phoenix.Channel
  use OpenTelemetryDecorator

  require Logger

  alias NervesHub.Archives
  alias NervesHub.AuditLogs.Templates
  alias NervesHub.Deployments
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares
  alias NervesHub.Helpers.Logging
  alias NervesHub.Repo
  alias Phoenix.Socket.Broadcast

  @decorate with_span("Channels.DeviceChannel.join")
  def join("device", params, %{assigns: %{device: device}} = socket) do
    case update_metadata(device, params) do
      {:ok, device} ->
        send(self(), {:after_join, params})

        {:ok, assign(socket, :device, device)}

      err ->
        Logger.warning("[DeviceChannel] failure to connect - #{inspect(err)}")
        {:error, %{error: "could not connect"}}
    end
  end

  @decorate with_span("Channels.DeviceChannel.handle_info:after_join")
  def handle_info({:after_join, params}, %{assigns: %{device: device}} = socket) do
    device =
      device
      |> Deployments.verify_deployment_membership()
      |> Deployments.set_deployment()

    maybe_send_public_keys(device, socket, params)

    # clear out any inflight updates, there shouldn't be one at this point
    # we might make a new one right below it, so clear it beforehand
    Devices.clear_inflight_update(device)

    deployment_channel = deployment_channel(device)

    subscribe("device:#{device.id}")
    subscribe(deployment_channel)

    send(self(), :device_registration)

    socket =
      socket
      |> assign(:device, device)
      |> assign(:deployment_channel, deployment_channel)
      |> assign_api_version(params)
      |> assign(:penalty_timer, nil)
      |> maybe_start_penalty_timer()
      |> maybe_send_archive()

    # Request device extension capabilities if possible
    # Earlier versions of nerves_hub_link don't have a fallback for unknown messages,
    # so check version before requesting extensions
    if safe_to_request_extensions?(socket.assigns.device_api_version),
      do: push(socket, "extensions:get", %{}),
      else: Templates.audit_unsupported_api_version(device)

    {:noreply, socket}
  end

  def handle_info(:device_registration, socket) do
    send(self(), {:device_registration, 0})
    {:noreply, socket}
  end

  def handle_info({:device_registration, 3}, socket) do
    # lets make sure we deregister any other connected devices using the same device id
    [:nerves_hub, :devices, :registry, :retries_exceeded]
    |> :telemetry.execute(%{}, %{device: socket.assigns.device})

    {:stop, :shutdown, socket}
  end

  @decorate with_span("Channels.DeviceChannel.handle_info:device_registration")
  def handle_info({:device_registration, attempt}, socket) do
    %{assigns: %{device: device}} = socket

    payload = %{
      deployment_id: device.deployment_id,
      firmware_uuid: get_in(device, [Access.key(:firmware_metadata), Access.key(:uuid)]),
      updates_enabled: device.updates_enabled && !Devices.device_in_penalty_box?(device),
      updating: false
    }

    case Registry.register(NervesHub.Devices.Registry, device.id, payload) do
      {:error, {:already_registered, _}} ->
        {:noreply, retry_device_registration(socket, attempt)}

      _ ->
        socket =
          socket
          |> assign(:registered?, true)
          |> assign(:registration_timer, nil)

        {:noreply, socket}
    end
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

  @decorate with_span("Channels.DeviceChannel.handle_info:deployments/update")
  def handle_info({"deployments/update", inflight_update}, %{assigns: %{device: device}} = socket) do
    device = deployment_preload(device)

    payload = Devices.resolve_update(device)

    case payload.update_available do
      true ->
        :telemetry.execute([:nerves_hub, :devices, :update, :automatic], %{count: 1}, %{
          identifier: device.identifier,
          firmware_uuid: inflight_update.firmware_uuid
        })

        # If we get here, the device is connected and high probability it receives
        # the update message so we can Audit and later assert on this audit event
        # as a loosely valid attempt to update
        Templates.audit_device_deployment_update_triggered(device, socket.assigns.reference_id)

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

  def handle_info(%Broadcast{event: "moved"}, %{assigns: %{device: device}} = socket) do
    _ = socket.endpoint.broadcast("device_socket:#{device.id}", "disconnect", %{})

    {:noreply, socket}
  end

  # Update local state and tell the various servers of the new information
  @decorate with_span("Channels.DeviceChannel.handle_info:devices-updated")
  def handle_info(%Broadcast{event: "devices/updated"}, %{assigns: %{device: device}} = socket) do
    device = Repo.reload(device)

    maybe_update_registry(socket, device, %{
      updates_enabled: device.updates_enabled && !Devices.device_in_penalty_box?(device)
    })

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

    maybe_update_registry(socket, device, %{
      updates_enabled: updates_enabled
    })

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

  def handle_info(%Broadcast{event: "connection:heartbeat"}, socket) do
    # Expected message that is not used here :)
    {:noreply, socket}
  end

  def handle_info(msg, socket) do
    # Ignore unhandled messages so that it doesn't crash the link process
    # preventing cascading problems.
    Logger.warning("[DeviceChannel] Unhandled handle_info message! - #{inspect(msg)}")

    Logging.log_to_sentry(
      socket.assigns.device,
      "[DeviceChannel] Unhandled handle_info message!",
      %{
        message: msg
      }
    )

    {:noreply, socket}
  end

  def handle_in("fwup_progress", %{"value" => percent}, %{assigns: %{device: device}} = socket) do
    device_internal_broadcast!(socket, device, "fwup_progress", %{percent: percent})

    # if this is the first fwup we see, then mark it as an update attempt
    if socket.assigns[:update_started?] do
      {:noreply, socket}
    else
      # reload update attempts because they might have been cleared
      # and we have a cached stale version
      updated_device = Repo.reload(device)
      device = %{device | update_attempts: updated_device.update_attempts}

      {:ok, device} = Devices.update_attempted(device)

      maybe_update_registry(socket, device, %{updating: true})

      socket =
        socket
        |> assign(:device, deployment_preload(device))
        |> assign(:update_started?, true)

      {:noreply, socket}
    end
  end

  def handle_in("connection_types", %{"values" => types}, %{assigns: %{device: device}} = socket) do
    {:ok, device} = Devices.update_device(device, %{"connection_types" => types})
    {:noreply, assign(socket, :device, device)}
  end

  def handle_in("status_update", %{"status" => _status}, socket) do
    # TODO store in tracker or the database?
    {:noreply, socket}
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

  def handle_in(msg, params, socket) do
    # Ignore unhandled messages so that it doesn't crash the link process
    # preventing cascading problems.
    Logger.warning(
      "[DeviceChannel] Unhandled handle_in message! - #{inspect(msg)} - #{inspect(params)}"
    )

    device = socket.assigns.device
    Logging.log_to_sentry(device, "[DeviceChannel] Unhandled handle_in message!", %{message: msg})

    {:noreply, socket}
  end

  defp assign_api_version(socket, params) do
    assign(socket, :device_api_version, Map.get(params, "device_api_version", "1.0.0"))
  end

  defp retry_device_registration(socket, attempt) do
    _ = if timer = socket.assigns[:registration_timer], do: Process.cancel_timer(timer)
    timer = Process.send_after(self(), {:device_registration, attempt + 1}, 500)
    assign(socket, registration_timer: timer)
  end

  defp maybe_update_registry(socket, device, updates) do
    _ =
      if socket.assigns[:registered?] do
        {_, _} =
          Registry.update_value(NervesHub.Devices.Registry, device.id, fn value ->
            Map.merge(value, updates)
          end)
      end

    :ok
  end

  defp subscribe(topic) do
    _ = Phoenix.PubSub.subscribe(NervesHub.PubSub, topic)
    :ok
  end

  defp unsubscribe(topic) do
    Phoenix.PubSub.unsubscribe(NervesHub.PubSub, topic)
  end

  defp device_internal_broadcast!(socket, device, event, payload) do
    topic = "device:#{device.identifier}:internal"
    socket.endpoint.broadcast_from!(self(), topic, event, payload)
  end

  defp maybe_send_public_keys(device, socket, params) do
    Enum.each(["fwup_public_keys", "archive_public_keys"], fn key_type ->
      if params[key_type] == "on_connect" do
        org_keys = NervesHub.Accounts.list_org_keys(device.org_id, false)

        push(socket, key_type, %{
          keys: Enum.map(org_keys, fn ok -> ok.key end)
        })
      end
    end)
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

  defp update_device(socket, device) do
    socket
    |> assign(:device, deployment_preload(device))
    |> update_deployment_subscription(device)
  end

  defp update_deployment_subscription(socket, device) do
    deployment_channel = deployment_channel(device)

    if deployment_channel != socket.assigns.deployment_channel do
      unsubscribe(socket.assigns.deployment_channel)
      subscribe(deployment_channel)

      maybe_update_registry(socket, device, %{deployment_id: device.deployment_id})

      assign(socket, :deployment_channel, deployment_channel)
    else
      socket
    end
  end

  defp deployment_channel(device) do
    if device.deployment_id do
      "deployment:#{device.deployment_id}"
    else
      "deployment:none"
    end
  end

  defp deployment_preload(device) do
    Repo.preload(device, [deployment: [:archive, :firmware]], force: true)
  end

  defp maybe_send_archive(socket) do
    device = deployment_preload(socket.assigns.device)

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

  defp safe_to_request_extensions?(version), do: Version.match?(version, ">= 2.2.0")
end
