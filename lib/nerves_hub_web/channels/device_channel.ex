defmodule NervesHubWeb.DeviceChannel do
  @moduledoc """
  Primary websocket channel for device communication

  Handles device logic for updating and tracking devices.

  # Fastlaned Messages

  - identify
  - reboot
  - update (scheduled and manual)
  - archive (but sent from within the channel process)
  - fwup_public_keys (but sent from within the channel process)
  - archive_public_keys (but sent from within the channel process)

  # Intercepted Messages

  - updated
  - deployment_updated
  """

  use Phoenix.Channel
  use OpenTelemetryDecorator

  alias NervesHub.DeviceLink
  alias NervesHub.Devices
  alias NervesHub.Repo
  alias Phoenix.Socket.Broadcast

  require Logger

  intercept(["updated", "deployment_updated"])

  @decorate with_span("Channels.DeviceChannel.join")
  def join("device:" <> _device_id, params, %{assigns: %{device: device, reference_id: reference_id}} = socket) do
    Logger.metadata(device_id: device.id, device_identifier: device.identifier)

    params = maybe_sanitize_device_api_version(params)

    case DeviceLink.join(device, reference_id, params) do
      {:ok, device} ->
        socket =
          socket
          |> assign(:currently_downloading_uuid, params["currently_downloading_uuid"])
          |> assign(:update_started?, !!params["currently_downloading_uuid"])
          |> assign(:device_api_version, params["device_api_version"])
          |> update_device(device)

        send(self(), {:after_join, params})

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

  def handle_info({:after_join, params}, socket) do
    %{device: device, reference_id: reference_id} = socket.assigns

    # :deployment_group is manually set to nil in DeviceLink, need to force reload here
    device = NervesHub.Repo.preload(device, :deployment_group, force: true)

    connecting_codes =
      [
        get_in(device, [Access.key(:deployment_group), Access.key(:connecting_code)]),
        device.connecting_code
      ]
      |> Enum.filter(&(not is_nil(&1) and byte_size(&1) > 0))

    case [safe_to_run_scripts?(socket), Enum.empty?(connecting_codes)] do
      [true, false] ->
        connecting_code = Enum.join(connecting_codes, "\n")
        # connecting code first incase it attempts to change things before the other messages
        push(socket, "scripts/run", %{"text" => connecting_code, "ref" => "connecting_code"})

      [false, false] ->
        connecting_code = Enum.join(connecting_codes, "\n")
        text = ~s/#{connecting_code}\n\r/
        topic = "device:console:#{device.id}"

        socket.endpoint.broadcast_from!(self(), topic, "dn", %{"data" => text})

      _ ->
        :ok
    end

    :ok = DeviceLink.after_join(device, reference_id, params)

    {:noreply, socket}
  end

  # we can ignore this message
  def handle_info(%Broadcast{event: "deployments/update"}, socket) do
    {:noreply, socket}
  end

  # listen for notifications about archive updates for deployments
  def handle_info(%Broadcast{event: "archives/updated"}, socket) do
    %{device: device, device_api_version: device_api_version, reference_id: reference_id} =
      socket.assigns

    DeviceLink.maybe_send_archive(device, device_api_version, reference_id, audit_log: true)
    {:noreply, socket}
  end

  def handle_info({:run_script, pid, text}, socket) do
    if safe_to_run_scripts?(socket) do
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

    %{device_api_version: device_api_version, reference_id: reference_id} = socket.assigns
    DeviceLink.maybe_send_archive(device, device_api_version, reference_id, audit_log: true)

    {:noreply, update_device(socket, device)}
  end

  def handle_out("deployment_updated", payload, socket) do
    device = %{socket.assigns.device | deployment_id: payload.deployment_id}

    %{device_api_version: device_api_version, reference_id: reference_id} = socket.assigns
    DeviceLink.maybe_send_archive(device, device_api_version, reference_id, audit_log: true)

    {:noreply, update_device(socket, device)}
  end

  def handle_in("firmware_validated", _, %{assigns: %{device: device}} = socket) do
    {:ok, device} = Devices.firmware_validated(device)

    {:noreply, assign(socket, :device, device)}
  end

  def handle_in("fwup_progress", %{"value" => percent}, %{assigns: %{device: device}} = socket) do
    DeviceLink.firmware_update_progress(device, percent)

    {:noreply, maybe_update_update_attempts(socket)}
  end

  def handle_in("connection_types", %{"values" => types}, socket) do
    DeviceLink.update_connection_metadata(socket.assigns.reference_id, %{
      "connection_types" => types
    })

    {:noreply, socket}
  end

  def handle_in("status_update", %{"status" => status}, socket) do
    DeviceLink.status_update(socket.assigns.device, status, socket.assigns.update_started?)

    {:noreply, socket}
  end

  def handle_in("rebooting", _, socket) do
    {:noreply, socket}
  end

  def handle_in(
        "scripts/run",
        %{"ref" => "connecting_code", "result" => result, "return" => return, "output" => output},
        socket
      )
      when result == "error" or return == "nil" do
    :telemetry.execute([:nerves_hub, :devices, :connecting_code_failure], %{
      output: output,
      identifier: socket.assigns.device.identifier
    })

    {:noreply, socket}
  end

  def handle_in("scripts/run", %{"ref" => "connecting_code"}, socket) do
    :telemetry.execute([:nerves_hub, :devices, :connecting_code_success], %{count: 1})

    {:noreply, socket}
  end

  def handle_in("scripts/run", params, socket) do
    if pid = get_in(socket.assigns, [:script_refs, params["ref"]]) do
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

  defp maybe_sanitize_device_api_version(%{"device_api_version" => version} = params) do
    case Version.parse(version) do
      {:ok, _} ->
        params

      :error ->
        Logger.warning("[DeviceChannel] invalid device_api_version value - #{inspect(params["device_api_version"])}")

        Map.put(params, "device_api_version", "1.0.0")
    end
  end

  defp maybe_sanitize_device_api_version(params) do
    Logger.warning("[DeviceChannel] device_api_version is missing from the connection params")
    Map.put(params, "device_api_version", "1.0.0")
  end

  # if we know the update has already started, we can move on
  def maybe_update_update_attempts(%{assigns: %{update_started?: true}} = socket), do: socket

  # if this is the first fwup we see, and we didn't know the update had already started,
  # then mark it as an update attempt
  #
  # we don't need to store the result as this information isn't used anywhere else
  def maybe_update_update_attempts(socket) do
    :ok = Devices.update_attempted(socket.assigns.device)

    assign(socket, :update_started?, true)
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

  defp safe_to_run_scripts?(socket), do: Version.match?(socket.assigns.device_api_version, ">= 2.1.0")
end
