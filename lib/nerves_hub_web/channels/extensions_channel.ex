defmodule NervesHubWeb.ExtensionsChannel do
  use Phoenix.Channel

  alias NervesHub.Extensions
  alias NervesHub.Helpers.Logging
  alias NervesHub.Repo
  alias Phoenix.PubSub
  alias Phoenix.Socket.Broadcast

  require Logger

  @impl Phoenix.Channel
  def join("extensions", extension_versions, socket) do
    # the assigns are not shared between channels, so if we don't
    # reload the device we are likely to have incorrect data, especially
    # after the first connect event
    socket = reload_device(socket)

    extensions = parse_extensions(socket.assigns.device, extension_versions)
    socket = assign(socket, :extensions, extensions)

    attach_list = for {key, %{attach?: true}} <- extensions, do: key

    if length(attach_list) > 0 do
      send(self(), :init_extensions)
    end

    # all devices are lumped into a `extensions` topic (the name used in join/3)
    # this can be a security issue as pubsub messages can be sent to all connected devices
    # additionally, this topic isn't needed or used, so we can unsubscribe from it
    :ok = socket.endpoint.unsubscribe("extensions")

    topic = "device:#{socket.assigns.device.id}:extensions"
    :ok = socket.endpoint.subscribe(topic)

    {:ok, attach_list, socket}
  end

  defp parse_extensions(
         %{extensions: device_extensions, product: %{extensions: product_extensions}},
         extension_versions
       ) do
    allowed_extensions =
      for {extension, true} <- Map.from_struct(product_extensions),
          {^extension, device_enabled?} <- Map.from_struct(device_extensions),
          device_enabled? != false,
          do: extension

    for {key_str, version} <- extension_versions, into: %{} do
      meta =
        case Version.parse(version) do
          {:ok, ver} ->
            extension = Enum.find(allowed_extensions, &(to_string(&1) == key_str))

            if extension do
              mod = Extensions.module(extension, ver)
              attach = Code.ensure_loaded?(mod) && mod.enabled?()
              %{attach?: attach, version: ver, module: mod, status: :detached}
            else
              %{attach?: false, version: version, module: nil, status: :detached}
            end

          _ ->
            %{attach?: false, version: version, module: nil, status: :detached}
        end

      {key_str, meta}
    end
  end

  @impl Phoenix.Channel
  def handle_in(scoped_event, payload, socket) do
    with [key, event] <- String.split(scoped_event, ":", parts: 2),
         %{attach?: true, module: mod} <- socket.assigns.extensions[key] do
      case event do
        "attached" ->
          update_in(socket.assigns.extensions[key], &%{&1 | status: :attached})
          |> mod.attach()

        "detached" ->
          update_in(socket.assigns.extensions[key], &%{&1 | status: :detached})
          |> mod.detach()

        "error" ->
          socket = update_in(socket.assigns.extensions[key], &%{&1 | status: :detached})
          safe_handle_in(mod, event, payload, socket)

        event ->
          safe_handle_in(mod, event, payload, socket)
      end
    else
      _ ->
        # Unknown extension, tell device to detach it
        {:reply, {:error, "detach"}, socket}
    end
  end

  defp safe_handle_in(mod, event, payload, socket) do
    mod.handle_in(event, payload, socket)
  rescue
    error ->
      Logger.warning("#{inspect(mod)} failed to handle extension message [#{event}] - #{inspect(error)}")

      Logging.log_to_sentry(socket.assigns.device, error)
      {:noreply, socket}
  end

  @impl Phoenix.Channel
  def handle_info(:init_extensions, socket) do
    topic = "product:#{socket.assigns.device.product.id}:extensions"
    :ok = PubSub.subscribe(NervesHub.PubSub, topic)

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
      Logging.log_to_sentry(socket.assigns.device, error)
      {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp reload_device(%{assigns: %{device: device}} = socket) do
    device =
      device
      |> Repo.reload()
      |> Repo.preload(:product)

    assign(socket, :device, device)
  end
end
