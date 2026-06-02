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
  alias NervesHub.Devices.Device
  alias Phoenix.Socket.Broadcast

  require Logger

  intercept(["updated", "deployment_updated"])

  @decorate with_span("Channels.DeviceChannel.join")
  def join("device:" <> _device_id, params, %{assigns: %{device_info: device_info}} = socket) do
    Logger.metadata(device_id: device_info.device_id, device_identifier: device_info.device_identifier)

    params = maybe_sanitize_device_api_version(params)

    case DeviceLink.join(device_info, params) do
      {:ok, device_info} ->
        socket =
          socket
          |> assign(:currently_downloading_uuid, params["currently_downloading_uuid"])
          |> assign(:device_api_version, params["device_api_version"])
          |> update_device_info(device_info)

        send(self(), {:after_join, params})

        {:ok, socket}

      err ->
        :telemetry.execute([:nerves_hub, :devices, :join_failure], %{count: 1}, %{
          identifier: device_info.device_identifier,
          channel: "device",
          error: err
        })

        {:error, %{error: "could not connect"}}
    end
  end

  @decorate with_span("Channels.DeviceChannel.handle_info:after_join")
  def handle_info({:after_join, params}, socket) do
    :ok = DeviceLink.after_join(socket.assigns.device_info, params)

    socket.assigns.device_info
    |> DeviceLink.fetch_connecting_code()
    |> send_connecting_code(safe_to_run_scripts?(socket), socket)

    {:noreply, socket}
  end

  # we can ignore this message
  def handle_info(%Broadcast{event: "deployments/update"}, socket) do
    {:noreply, socket}
  end

  # listen for notifications about archive updates for deployments
  def handle_info(%Broadcast{event: "archives/updated"}, socket) do
    %{device_info: device_info, device_api_version: device_api_version} =
      socket.assigns

    DeviceLink.maybe_send_archive(device_info, device_api_version, audit_log: true)

    {:noreply, socket}
  end

  @decorate with_span("Channels.DeviceChannel.handle_info:run_script")
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
      identifier: socket.assigns.device_info.device_identifier,
      msg: msg
    })

    {:noreply, socket}
  end

  # Update local state and tell the various servers of the new information
  @decorate with_span("Channels.DeviceChannel.handle_out:updated")
  def handle_out("updated", _, %{assigns: %{device_info: device_info}} = socket) do
    device_info = DeviceLink.refresh_device_info(device_info)

    %{device_api_version: device_api_version} = socket.assigns
    DeviceLink.maybe_send_archive(device_info, device_api_version, audit_log: true)

    {:noreply, update_device_info(socket, device_info)}
  end

  @decorate with_span("Channels.DeviceChannel.handle_out:deployment_updated")
  def handle_out("deployment_updated", payload, socket) do
    device_info = %{socket.assigns.device_info | deployment_id: payload.deployment_id}

    %{device_api_version: device_api_version} = socket.assigns
    DeviceLink.maybe_send_archive(device_info, device_api_version, audit_log: true)

    {:noreply, update_device_info(socket, device_info)}
  end

  @decorate with_span("Channels.DeviceChannel.handle_in:firmware_validated")
  def handle_in("firmware_validated", _, %{assigns: %{device_info: device_info}} = socket) do
    Devices.firmware_validated(device_info)

    {:noreply, socket}
  end

  @decorate with_span("Channels.DeviceChannel.handle_in:fwup_progress")
  def handle_in("fwup_progress", %{"value" => percent} = params, %{assigns: %{device_info: device_info}} = socket) do
    {stage, percent} =
      case {params["stage"], percent} do
        {nil, 100} -> {"completed", nil}
        {nil, _} -> {"updating", percent}
        {stage, _} -> {stage, percent}
      end

    DeviceLink.status_update(device_info, %{"status" => stage, "progress" => percent})

    {:noreply, socket}
  end

  @decorate with_span("Channels.DeviceChannel.handle_in:connection_types")
  def handle_in("connection_types", %{"values" => types}, socket) do
    :ok =
      DeviceLink.update_connection_metadata(socket.assigns.device_info.connection_ref, %{
        "connection_types" => types
      })

    {:noreply, socket}
  end

  @decorate with_span("Channels.DeviceChannel.handle_in:status_update")
  def handle_in("status_update", params, socket) do
    DeviceLink.status_update(socket.assigns.device_info, params)

    {:noreply, socket}
  end

  def handle_in("rebooting", _, socket) do
    {:noreply, socket}
  end

  @decorate with_span("Channels.DeviceChannel.handle_in:scripts/run")
  def handle_in(
        "scripts/run",
        %{"ref" => "connecting_code", "result" => result, "return" => return, "output" => output},
        socket
      )
      when result == "error" or return == "nil" do
    :telemetry.execute([:nerves_hub, :devices, :connecting_code_failure], %{
      output: output,
      identifier: socket.assigns.device_info.device_identifier
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

  @decorate with_span("Channels.DeviceChannel.handle_in:report_network_interface")
  def handle_in(
        "report_network_interface",
        %{"interface" => interface},
        %{assigns: %{device_info: device_info}} = socket
      ) do
    if Device.humanized_network_interface_name(interface) == device_info.device_network_interface do
      {:noreply, socket}
    else
      case Devices.update_network_interface(device_info.device_id, interface) do
        {:ok, device} ->
          {:noreply, assign(socket, :device_info, %{device_info | device_network_interface: device.network_interface})}

        {:error, changeset} ->
          Logger.warning(
            "[DeviceChannel] could not update device network interface because: #{inspect(changeset.errors)}"
          )

          {:noreply, socket}
      end
    end
  end

  def handle_in(msg, params, %{assigns: %{device_info: device_info}} = socket) do
    # Ignore unhandled messages so that it doesn't crash the link process
    # preventing cascading problems.
    :telemetry.execute([:nerves_hub, :devices, :unhandled_in], %{count: 1}, %{
      identifier: device_info.device_identifier,
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

  defp send_connecting_code(nil, _, _), do: :ok

  defp send_connecting_code(connecting_code, true, socket) when is_list(connecting_code) do
    connecting_code = Enum.join(connecting_code, "\n")
    # connecting code first in the case it attempts to change things before the other messages
    push(socket, "scripts/run", %{"text" => connecting_code, "ref" => "connecting_code"})
  end

  defp send_connecting_code(connecting_code, false, socket) when is_list(connecting_code) do
    connecting_code = Enum.join(connecting_code, "\n")
    text = ~s/#{connecting_code}\n\r/
    topic = "device:console:#{socket.assigns.device_info.device_id}"

    socket.endpoint.broadcast_from!(self(), topic, "dn", %{"data" => text})
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

  defp update_device_info(socket, device_info) do
    socket
    |> assign(:device_info, device_info)
    |> update_deployment_group_subscription(device_info)
  end

  defp update_deployment_group_subscription(socket, device_info) do
    deployment_channel = deployment_channel(device_info)

    if deployment_channel == socket.assigns[:deployment_channel] do
      socket
    else
      unsubscribe(socket.assigns[:deployment_channel])
      subscribe(deployment_channel)

      assign(socket, :deployment_channel, deployment_channel)
    end
  end

  defp deployment_channel(device_info) do
    if device_info.deployment_id do
      "deployment:#{device_info.deployment_id}"
    end
  end

  defp safe_to_run_scripts?(socket), do: Version.match?(socket.assigns.device_api_version, ">= 2.1.0")
end
