defmodule NervesHubWeb.DeviceChannel do
  @moduledoc """
  Primary websocket channel for device communication

  Handles device logic for updating and tracking devices.

  # Fastlaned Messages

  - identify
  - reboot
  - update (scheduled and manual)

  # Intercepted Messages

  - updated
  - deployment_updated
  """

  use Phoenix.Channel
  use OpenTelemetryDecorator

  alias NervesHub.Archives
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares
  alias NervesHub.ManagedDeployments
  alias NervesHub.Repo
  alias Phoenix.Socket.Broadcast

  intercept(["updated", "deployment_updated"])

  @decorate with_span("Channels.DeviceChannel.join")
  def join("device", params, %{assigns: %{device: device}} = socket) do
    case update_metadata(device, params) do
      {:ok, device} ->
        send(self(), {:after_join, params})

        socket =
          socket
          |> assign(:currently_downloading_uuid, params["currently_downloading_uuid"])
          |> assign(:update_started?, !!params["currently_downloading_uuid"])
          |> assign(:device, device)

        maybe_clear_inflight_update(device, !!params["currently_downloading_uuid"])

        {:ok, socket}

      err ->
        :telemetry.execute([:nerves_hub, :devices, :join_failure], %{count: 1}, %{
          identifier: device.identifier,
          channel: "device",
          error: err
        })

        {:error, %{error: "could not connect"}}
    end
  end

  @decorate with_span("Channels.DeviceChannel.handle_info:after_join")
  def handle_info({:after_join, params}, %{assigns: %{device: device}} = socket) do
    device =
      device
      |> ManagedDeployments.verify_deployment_group_membership()
      |> ManagedDeployments.set_deployment_group()
      |> Map.put(:deployment_group, nil)

    maybe_send_public_keys(device, socket, params)

    socket =
      socket
      |> update_device(device)
      |> setup_pubsub_subscription()
      |> assign_api_version(params)
      |> maybe_send_archive()

    send(self(), :announce_online)

    # Request device extension capabilities if possible
    # Earlier versions of nerves_hub_link don't have a fallback for unknown messages,
    # so check version before requesting extensions
    if safe_to_request_extensions?(socket.assigns.device_api_version),
      do: push(socket, "extensions:get", %{})

    {:noreply, socket}
  end

  # Let the deployment orchestrator know that we are online
  def handle_info(:announce_online, socket) do
    # Update the connection to say that we are fully up and running
    Connections.device_connected(socket.assigns.reference_id)
    # Tell the tracker that we are online
    NervesHub.Tracker.online(socket.assigns.device)
    # tell the orchestrator that we are online
    Devices.deployment_device_online(socket.assigns.device)

    {:noreply, socket}
  end

  # we can ignore this message
  def handle_info(%Broadcast{event: "deployments/update"}, socket) do
    {:noreply, socket}
  end

  # listen for notifications about archive updates for deployments
  def handle_info(%Broadcast{event: "archives/updated"}, socket) do
    {:noreply, maybe_send_archive(socket, audit_log: true)}
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
    script_refs =
      socket.assigns
      |> Map.get(:script_refs, %{})
      |> Map.delete(ref)

    socket = assign(socket, :script_refs, script_refs)

    {:noreply, socket}
  end

  # Ignore unhandled messages, and send some telemetry
  def handle_info(msg, socket) do
    :telemetry.execute([:nerves_hub, :devices, :unhandled_info], %{count: 1}, %{
      identifier: socket.assigns.device.identifier,
      msg: msg
    })

    {:noreply, socket}
  end

  # Update local state and tell the various servers of the new information
  def handle_out("updated", _, %{assigns: %{device: device}} = socket) do
    device = Repo.reload(device)

    socket =
      socket
      |> update_device(device)
      |> maybe_send_archive(audit_log: true)

    {:noreply, socket}
  end

  def handle_out("deployment_updated", payload, socket) do
    device = %{socket.assigns.device | deployment_id: payload.deployment_id}

    socket =
      socket
      |> update_device(device)
      |> maybe_send_archive(audit_log: true)

    {:noreply, socket}
  end

  def handle_in("fwup_progress", %{"value" => percent}, %{assigns: %{device: device}} = socket) do
    device_internal_broadcast!(socket, device, "fwup_progress", %{
      device_id: device.id,
      percent: percent
    })

    # if we know the update has already started, we can move on
    if socket.assigns.update_started? do
      {:noreply, socket}
    else
      # if this is the first fwup we see, and we didn't know the update had already started,
      # then mark it as an update attempt
      #
      # reload update attempts because they might have been cleared
      # and we have a cached stale version
      updated_device = Repo.reload(device)
      device = %{device | update_attempts: updated_device.update_attempts}

      {:ok, device} = Devices.update_attempted(device)

      socket =
        socket
        |> assign(:device, device)
        |> assign(:update_started?, true)

      {:noreply, socket}
    end
  end

  def handle_in("connection_types", %{"values" => types}, socket) do
    :ok =
      Connections.merge_update_metadata(socket.assigns.reference_id, %{
        "connection_types" => types
      })

    {:noreply, socket}
  end

  def handle_in("status_update", %{"status" => status}, socket) do
    # a temporary hook into failed updates
    if String.contains?(status, "fwup error") do
      # if there was an error during updating, clear the inflight update
      reset_updating_status(socket)
    end

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

  def handle_in(msg, params, %{assigns: %{device: device}} = socket) do
    # Ignore unhandled messages so that it doesn't crash the link process
    # preventing cascading problems.
    :telemetry.execute([:nerves_hub, :devices, :unhandled_in], %{count: 1}, %{
      identifier: device.identifier,
      msg: msg,
      params: params
    })

    {:noreply, socket}
  end

  defp assign_api_version(%{assigns: %{reference_id: ref_id}} = socket, params) do
    version = Map.get(params, "device_api_version", "1.0.0")

    :ok = Connections.merge_update_metadata(ref_id, %{"device_api_version" => version})

    assign(socket, :device_api_version, version)
  end

  defp setup_pubsub_subscription(%{assigns: %{device: device}} = socket) do
    # all devices are lumped into a `device` topic (the name used in join/3)
    # this can be a security issue pubsub messages can be sent to all connected devices
    # additionally, this topic isn't needed or used, so we can unsubscribe from it
    unsubscribe("device")

    topic = "device:#{device.id}"

    # instead, we subscribe to `device:device.id` and setup fastlaning and intercepts so that
    # we have the option of not acting as a middleman to all messages going to a device
    %{transport_pid: transport_pid, serializer: serializer, pubsub_server: pubsub_server} = socket
    fastlane = {:fastlane, transport_pid, serializer, __MODULE__.__intercepts__()}

    :ok = Phoenix.PubSub.subscribe(pubsub_server, topic, metadata: fastlane)

    %{socket | topic: topic}
  end

  defp subscribe(topic) when not is_nil(topic) do
    _ = Phoenix.PubSub.subscribe(NervesHub.PubSub, topic)
    :ok
  end

  defp subscribe(nil), do: :ok

  defp unsubscribe(topic) when not is_nil(topic) do
    Phoenix.PubSub.unsubscribe(NervesHub.PubSub, topic)
  end

  defp unsubscribe(nil), do: :ok

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
  defp update_metadata(%Device{firmware_metadata: %{uuid: uuid}} = device, %{"nerves_fw_uuid" => uuid}) do
    {:ok, device}
  end

  # A new UUID is being reported from an update
  defp update_metadata(%{firmware_metadata: previous_metadata} = device, params) do
    with {:ok, metadata} <- Firmwares.metadata_from_device(params),
         {:ok, device} <- Devices.update_firmware_metadata(device, metadata) do
      Devices.firmware_update_successful(device, previous_metadata)
    end
  end

  @spec maybe_clear_inflight_update(device :: Device.t(), currently_updating? :: boolean()) :: :ok
  defp maybe_clear_inflight_update(device, false) do
    Devices.clear_inflight_update(device)
    :ok
  end

  defp maybe_clear_inflight_update(_device, true) do
    :ok
  end

  defp reset_updating_status(socket) do
    Devices.clear_inflight_update(socket.assigns.device)
  end

  defp update_device(socket, device) do
    socket
    |> assign(:device, device)
    |> update_deployment_group_subscription(device)
  end

  defp update_deployment_group_subscription(socket, device) do
    deployment_channel = deployment_channel(device)

    if deployment_channel == socket.assigns[:deployment_channel] do
      socket
    else
      unsubscribe(socket.assigns[:deployment_channel])
      subscribe(deployment_channel)

      assign(socket, :deployment_channel, deployment_channel)
    end
  end

  defp deployment_channel(device) do
    if device.deployment_id do
      "deployment:#{device.deployment_id}"
    end
  end

  defp maybe_send_archive(socket, opts \\ [])

  defp maybe_send_archive(%{assigns: %{deployment_id: nil}} = socket, _opts), do: socket

  defp maybe_send_archive(%{assigns: %{device: device}} = socket, opts) do
    opts = Keyword.validate!(opts, audit_log: false)
    updates_enabled = device.updates_enabled && !Devices.device_in_penalty_box?(device)
    version_match = Version.match?(socket.assigns.device_api_version, ">= 2.0.0")

    if updates_enabled && version_match do
      if archive = Archives.archive_for_deployment_group(device.deployment_id) do
        if opts[:audit_log],
          do:
            DeviceTemplates.audit_device_archive_update_triggered(
              device,
              archive,
              socket.assigns.reference_id
            )

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
